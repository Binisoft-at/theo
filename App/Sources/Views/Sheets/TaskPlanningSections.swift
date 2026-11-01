import SwiftUI
import TheoCore

/// Details-sheet sections for planning a task: estimate and focus, repeat and reminders,
/// and its place on the Eisenhower matrix.
struct TaskPlanningSections: View {
    @Bindable var task: TaskItem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var customEstimate = ""
    @State private var customMinutes = 45

    private static let nudgeOptions: [(title: String, count: Int, every: Int)] = [
        ("Off", 0, 0), ("3× every 5 min", 3, 5), ("3× every 10 min", 3, 10), ("5× every 15 min", 5, 15), ("4× every 30 min", 4, 30),
    ]

    var body: some View {
        estimateSection
        if task.dueDate != nil {
            repeatSection
        }
        matrixSection
    }

    // MARK: - Estimate & focus

    private var estimateSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PowerHours.presets, id: \.self) { value in
                        ChipButton(title: PowerHours.number(value), color: .teal, isOn: task.estimate == value) {
                            app.store.setEstimate([task], task.estimate == value ? 0 : value)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            HStack {
                Label("Custom", systemImage: "slider.horizontal.3")
                Spacer()
                TextField(task.estimate > 0 && !PowerHours.presets.contains(task.estimate) ? PowerHours.number(task.estimate) : "PH", text: $customEstimate)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onSubmit(applyCustomEstimate)
                    .onChange(of: customEstimate) { _, _ in
                        if PowerHours.parse(customEstimate) != nil { applyCustomEstimate() }
                    }
            }
            if task.focusSeconds >= 60 {
                LabeledContent("Focused", value: PowerHours.format(task.focusSeconds / (PowerHours.minutesPerPH * 60)))
            }
            if !task.isDone {
                Button {
                    let target = task
                    let model = app
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        model.startFocus(on: target)
                    }
                } label: {
                    Label("Start Focus", systemImage: "timer")
                }
            }
        } header: {
            Text("Estimate · Power Hours")
        } footer: {
            Text("1 PH = 50 minutes of focused work. Focus time is booked on the task.")
        }
    }

    private func applyCustomEstimate() {
        guard let value = PowerHours.parse(customEstimate) else { return }
        app.store.setEstimate([task], value)
    }

    // MARK: - Repeat & reminders

    private var repeatSection: some View {
        Section {
            Picker(selection: recurrenceBinding) {
                Text("Never").tag(Recurrence?.none)
                ForEach(Recurrence.common, id: \.self) { recurrence in
                    Text(recurrence.title).tag(Recurrence?.some(recurrence))
                }
            } label: {
                Label("Repeat", systemImage: "repeat")
            }
            if task.dueHasTime {
                DisclosureGroup {
                    ForEach(Reminders.presets, id: \.self) { offset in
                        Toggle(Reminders.describe(offset), isOn: reminderBinding(offset))
                    }
                    ForEach(customOffsets, id: \.self) { offset in
                        Toggle(Reminders.describe(offset), isOn: reminderBinding(offset))
                    }
                    HStack {
                        Stepper("\(customMinutes) min before", value: $customMinutes, in: 5...10080, step: 5)
                        Button("Add") {
                            app.store.setReminders(task, task.reminderOffsets + [customMinutes])
                        }
                        .buttonStyle(.borderless)
                    }
                    Picker("After the time", selection: nudgeBinding) {
                        ForEach(Self.nudgeOptions.indices, id: \.self) { index in
                            Text(Self.nudgeOptions[index].title).tag(index)
                        }
                    }
                } label: {
                    LabeledContent {
                        Text(reminderSummary)
                    } label: {
                        Label("Reminders", systemImage: "bell")
                    }
                }
            } else {
                Text("Give the deadline a time to get reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Repeat & Reminders")
        } footer: {
            if task.recurrence != nil {
                Text("Checking it off schedules the next one.")
            }
        }
    }

    private var recurrenceBinding: Binding<Recurrence?> {
        Binding(get: { task.recurrence }, set: { app.store.setRecurrence([task], $0) })
    }

    private func reminderBinding(_ offset: Int) -> Binding<Bool> {
        Binding(
            get: { task.reminderOffsets.contains(offset) },
            set: { on in
                var offsets = task.reminderOffsets.filter { $0 != offset }
                if on { offsets.append(offset) }
                app.store.setReminders(task, offsets)
            }
        )
    }

    /// Reminders before the time that aren't one of the presets.
    private var customOffsets: [Int] {
        task.reminderOffsets.filter { $0 > 0 && !Reminders.presets.contains($0) }
    }

    private var nudgeBinding: Binding<Int> {
        Binding(
            get: {
                let after = task.reminderOffsets.filter { $0 < 0 }
                return Self.nudgeOptions.firstIndex { Reminders.nudges(count: $0.count, every: $0.every) == after.sorted(by: >) } ?? 0
            },
            set: { index in
                let option = Self.nudgeOptions[index]
                let before = task.reminderOffsets.filter { $0 >= 0 }
                app.store.setReminders(task, before + Reminders.nudges(count: option.count, every: option.every))
            }
        )
    }

    private var reminderSummary: String {
        let offsets = task.reminderOffsets
        if offsets.isEmpty { return "Off" }
        if offsets == [0] { return "At time" }
        return "\(offsets.count) set"
    }

    // MARK: - Matrix

    private var matrixSection: some View {
        let effective = task.matrixPosition(today: app.dayStart)
        return Section {
            GeometryReader { geo in
                ZStack {
                    MatrixBackground(compact: true)
                    MatrixDot(urgency: task.urgency, importance: task.importance, effective: effective, isSelected: true, size: geo.size)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let position = MatrixGeometry.position(of: location, in: geo.size)
                    withAnimation(.snappy) { app.store.setMatrix(task, urgency: position.urgency, importance: position.importance) }
                }
            }
            .frame(height: 190)
            LabeledContent("Rank", value: MatrixGeometry.describe(urgency: effective.urgency, importance: effective.importance))
        } header: {
            Text("Eisenhower Matrix")
        } footer: {
            Text("Tap where it belongs. Priority adds importance, a close deadline adds urgency.")
        }
    }
}
