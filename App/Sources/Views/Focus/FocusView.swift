import SwiftUI
import Combine
import TheoCore

/// The focus timer: one Power Hour of focus (50 minutes by default), then a break. Focused
/// time is booked on the task and counts toward today's total.
struct FocusView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let session = app.focus {
                    running(session)
                } else {
                    idle
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Focus")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onReceive(clock) { date in
            now = date
            app.tickFocus(now: date)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func running(_ session: FocusSession) -> some View {
        let remaining = session.remaining(at: now)
        let progress = session.duration > 0 ? 1 - remaining / session.duration : 0
        let isRest = session.phase == .rest
        let task = session.taskID.flatMap { app.store.task(id: $0) }
        return VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text(isRest ? "Break" : (session.isPaused && session.rounds > 0 ? "Ready for the next round" : "Focus"))
                    .font(.headline)
                    .foregroundStyle(isRest ? Color.green : Color.accentColor)
                Text(session.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            ZStack {
                ProgressRing(progress: progress, lineWidth: 14)
                    .tint(isRest ? Color.green : Color.accentColor)
                VStack(spacing: 4) {
                    Text(Self.clockText(remaining))
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    if session.isPaused {
                        Text("Paused")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 260, height: 260)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isRest ? "Break" : "Focus")
            .accessibilityValue("\(Self.clockText(remaining)) left")

            HStack(spacing: 6) {
                ForEach(0..<max(session.rounds, 1), id: \.self) { index in
                    Circle()
                        .fill(index < session.rounds ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel("\(session.rounds) rounds done")

            HStack(spacing: 12) {
                Button {
                    if session.isPaused { app.resumeFocus() } else { app.pauseFocus() }
                } label: {
                    Label(session.isPaused ? (session.rounds > 0 && !isRest ? "Start" : "Resume") : "Pause",
                          systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    app.extendFocus(minutes: 5)
                } label: {
                    Label("+5 min", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                if isRest {
                    Button("Skip Break") { app.skipBreak() }
                        .buttonStyle(.glass)
                }
                if let task, !task.isDone {
                    Button {
                        withAnimation(.snappy) { app.store.setDone([task], true) }
                        app.stopFocus()
                    } label: {
                        Label("Task Done", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.glass)
                }
                Button(role: .destructive) {
                    app.stopFocus()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
            }

            totals(task: task)
            Spacer(minLength: 0)
        }
    }

    private var idle: some View {
        VStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Focus for one Power Hour")
                .font(.title3.weight(.semibold))
            Text("\(Int(app.focusMinutes)) minutes of focus, then a \(Int(app.breakMinutes))-minute break. Start it from a task to book the time on it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                app.startFocus(on: nil)
            } label: {
                Label("Start Focus", systemImage: "play.fill")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            totals(task: nil)
            Spacer(minLength: 0)
        }
    }

    private func totals(task: TaskItem?) -> some View {
        let phPerSecond = 1 / (PowerHours.minutesPerPH * 60)
        let today = FocusLog.seconds(on: now) * phPerSecond
        return VStack(spacing: 4) {
            Text("Today: \(PowerHours.format(today)) focused")
                .font(.subheadline.weight(.medium))
            if let task {
                let spent = task.focusSeconds * phPerSecond
                Text(task.estimate > 0
                     ? "On this task: \(PowerHours.number(spent)) of \(PowerHours.format(task.estimate))"
                     : "On this task: \(PowerHours.format(spent))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// "Focus 23:41" — shown on Today while a timer runs; tap opens it.
struct FocusPill: View {
    let session: FocusSession
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button {
                app.showFocus = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: session.phase == .rest ? "cup.and.saucer.fill" : "timer")
                    Text(session.phase == .rest ? "Break" : "Focus")
                    Text(FocusView.clockText(session.remaining(at: context.date)))
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(session.phase == .rest ? Color.green : Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.phase == .rest ? "Break running" : "Focus running")
        }
    }
}
