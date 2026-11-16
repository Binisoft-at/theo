import SwiftUI
import TheoCore

/// Details-sheet sections for planning a task: repeat and reminders, estimate and focus, and
/// (folded away) its importance level and place on the Eisenhower matrix.
struct TaskPlanningSections: View {
    @Bindable var task: TaskItem
    /// Inside the Mac inspector rather than a sheet: there's nothing to dismiss before the
    /// focus timer opens.
    var embedded = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var customEstimate = ""
    @State private var customMinutes = 45
    /// Ranking is set less often than the rest, so it starts folded.
    @State private var showsRanking = false
    /// Counts taps on the Power Hours chips, for the iPhone's selection tick.
    @State private var estimateTick = 0
    /// The accent chosen in Settings: the matrix dot takes a colour rather than the tint.
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue

    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .notes).color }

    private static let nudgeOptions: [(title: String, count: Int, every: Int)] = [
        ("Off", 0, 0), ("3× every 5 min", 3, 5), ("3× every 10 min", 3, 10), ("5× every 15 min", 5, 15), ("4× every 30 min", 4, 30),
    ]

    var body: some View {
        if task.dueDate != nil {
            repeatSection
        }
        estimateSection
        rankingSection
    }

    // MARK: - Estimate & focus

    private var estimateSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PowerHours.presets, id: \.self) { value in
                        ChipButton(title: PowerHours.number(value), color: Tint.powerHours, isOn: task.estimate == value) {
                            estimateTick += 1
                            Motion.animate(Motion.tap) {
                                app.store.setEstimate([task], task.estimate == value ? 0 : value)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: estimateTick)
            #endif
            customEstimateRow
            if task.focusSeconds >= 60 {
                LabeledContent {
                    Text(PowerHours.format(task.focusSeconds / (PowerHours.minutesPerPH * 60)))
                        .monospacedDigit()
                } label: {
                    SheetRowLabel("Focused")
                }
            }
            if !task.isDone {
                Button(action: startFocus) {
                    SheetRowLabel("Start Focus", action: "scope")
                }
            }
        } header: {
            Text("Estimate · Power Hours")
        } footer: {
            Text("1 PH = 50 minutes of focused work. Focus time is booked on the task.")
        }
    }

    /// Any other amount, typed: it applies as soon as it reads as a number.
    private var customEstimateRow: some View {
        HStack {
            SheetRowLabel("Custom", symbol: "slider.horizontal.3", color: Tint.powerHours)
            Spacer()
            TextField(customPlaceholder, text: $customEstimate)
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
    }

    /// The task's own amount when it isn't one of the chips.
    private var customPlaceholder: String {
        task.estimate > 0 && !PowerHours.presets.contains(task.estimate) ? PowerHours.number(task.estimate) : "PH"
    }

    private func applyCustomEstimate() {
        guard let value = PowerHours.parse(customEstimate) else { return }
        app.store.setEstimate([task], value)
    }

    private func startFocus() {
        if embedded {
            app.startFocus(on: task)
        } else {
            // The timer opens once the sheet is gone.
            let target = task
            let model = app
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                model.startFocus(on: target)
            }
        }
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
                SheetRowLabel("Repeat", symbol: "repeat")
            }
            if task.dueHasTime {
                remindersGroup
            } else {
                // Where the reminders will be, once the deadline has a time.
                Label {
                    Text("Give the deadline a time to get reminders.")
                } icon: {
                    SheetRowIcon("bell.slash")
                }
                .theoFont(.footnote)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Repeat & Reminders")
        } footer: {
            if task.recurrence != nil {
                Text(task.isOngoing
                    ? "Checking it off logs it and moves the deadline to the next time."
                    : "Checking it off schedules the next one.")
            }
        }
    }

    /// Reminders before the time and nudges after it, folded behind one row that says how
    /// many there are.
    private var remindersGroup: some View {
        DisclosureGroup {
            ForEach(Reminders.presets, id: \.self) { offset in
                Toggle(Reminders.describe(offset), isOn: reminderBinding(offset))
            }
            ForEach(customOffsets, id: \.self) { offset in
                Toggle(Reminders.describe(offset), isOn: reminderBinding(offset))
            }
            HStack {
                Stepper(value: $customMinutes, in: 5...10080, step: 5) {
                    Text("\(customMinutes) min before")
                        .rollingNumber(customMinutes)
                }
                #if os(iOS)
                .sensoryFeedback(.increase, trigger: customMinutes) { old, new in new > old }
                .sensoryFeedback(.decrease, trigger: customMinutes) { old, new in new < old }
                #endif
                Button("Add") {
                    Motion.animate(Motion.list) {
                        app.store.setReminders(task, task.reminderOffsets + [customMinutes])
                    }
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
                    .contentTransition(.numericText())
                    .animation(Motion.resolved(Motion.tap), value: reminderSummary)
            } label: {
                SheetRowLabel("Reminders", symbol: "bell")
            }
        }
    }

    private var recurrenceBinding: Binding<Recurrence?> {
        Binding(
            get: { task.recurrence },
            set: { recurrence in
                Motion.animate(Motion.list) { app.store.setRecurrence([task], recurrence) }
            }
        )
    }

    private func reminderBinding(_ offset: Int) -> Binding<Bool> {
        Binding(
            get: { task.reminderOffsets.contains(offset) },
            set: { on in
                var offsets = task.reminderOffsets.filter { $0 != offset }
                if on { offsets.append(offset) }
                Motion.animate(Motion.list) { app.store.setReminders(task, offsets) }
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
                Motion.animate(Motion.tap) {
                    app.store.setReminders(task, before + Reminders.nudges(count: option.count, every: option.every))
                }
            }
        )
    }

    private var reminderSummary: String {
        let offsets = task.reminderOffsets
        if offsets.isEmpty { return "Off" }
        if offsets == [0] { return "At time" }
        return "\(offsets.count) set"
    }

    // MARK: - Ranking

    /// The importance level and the matrix, folded behind one row that says where the task
    /// ranks. The priority marks above already set a matching importance. The dot glides to the
    /// cell that's tapped, and the row's words follow.
    private var rankingSection: some View {
        let cell = MatrixGeometry.cell(of: task, today: app.dayStart)
        return Section {
            DisclosureGroup(isExpanded: $showsRanking.animation(Motion.resolved(Motion.list))) {
                Stepper(value: importanceLevelBinding, in: 1...Matrix.levels) {
                    LabeledContent {
                        Text("\(task.importanceLevel) of \(Matrix.levels)")
                            .rollingNumber(task.importanceLevel)
                    } label: {
                        Text("Importance")
                    }
                }
                MatrixBoard(compact: true) { size in
                    MatrixDot(point: MatrixGeometry.center(of: cell, in: size), color: accent, isSelected: true)
                        .animation(Motion.resolved(Motion.tap), value: cell.key)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let target = MatrixGeometry.cell(at: location, in: size)
                            Motion.animate(Motion.tap) {
                                app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart)
                            }
                        }
                }
                .frame(height: 170)
                .sensoryFeedback(.selection, trigger: cell.key)
            } label: {
                LabeledContent {
                    Text(MatrixGeometry.describe(cell))
                        .contentTransition(.numericText())
                        .animation(Motion.resolved(Motion.tap), value: cell.key)
                } label: {
                    SheetRowLabel("Ranking", symbol: "square.grid.3x3", color: Tint.priority)
                }
            }
        } footer: {
            if showsRanking {
                Text("Urgency × importance. Tap a cell: left is due today, right is two weeks out or no date, up is more important. Lists are ranked by it.")
            }
        }
    }

    private var importanceLevelBinding: Binding<Int> {
        Binding(
            get: { task.importanceLevel },
            set: { level in
                Motion.animate(Motion.tap) { app.store.setImportance([task], Matrix.importance(forLevel: level)) }
            }
        )
    }
}
