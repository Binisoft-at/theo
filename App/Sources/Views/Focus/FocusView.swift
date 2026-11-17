import SwiftUI
import Combine
import TheoCore

/// Not started, running or paused: what the timer's start and stop haptics follow.
private enum FocusRunState {
    case idle, running, paused
}

/// The timer starting and stopping can be felt: SwiftUI plays its start and stop taps on the
/// watch only, so the iPhone gets a light tap for both. A finished round is a success. A
/// modifier of its own with typed conditions, so the timer's body stays quick to type-check.
private struct FocusHaptics: ViewModifier {
    let state: FocusRunState
    let rounds: Int

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.start, trigger: state, condition: Self.started)
            .sensoryFeedback(.stop, trigger: state, condition: Self.stopped)
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light), trigger: state)
            #endif
            .sensoryFeedback(.success, trigger: rounds, condition: Self.roundDone)
    }

    private static func started(_ old: FocusRunState, _ new: FocusRunState) -> Bool { new == .running }
    private static func stopped(_ old: FocusRunState, _ new: FocusRunState) -> Bool { old == .running }
    private static func roundDone(_ old: Int, _ new: Int) -> Bool { new > old }
}

/// The focus timer: one Power Hour of focus (50 minutes by default), then a break. Focused
/// time is booked on the task and counts toward today's total.
struct FocusView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    private var runState: FocusRunState {
        guard let focus = app.focus else { return .idle }
        return focus.isPaused ? .paused : .running
    }

    /// Something small that comes and goes in place (Skip Break).
    private static let popIn: AnyTransition = .scale(scale: 0.92).combined(with: .opacity)

    var body: some View {
        NavigationStack {
            Group {
                if let session = app.focus {
                    running(session)
                        .transition(.blurReplace)
                } else {
                    idle
                        .transition(.blurReplace)
                }
            }
            .animation(Motion.resolved(Motion.layout), value: app.focus == nil)
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
        .onReceive(clock) { tick($0) }
        .modifier(FocusHaptics(state: runState, rounds: app.focus?.rounds ?? 0))
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #else
        .presentationDetents([.large])
        #endif
    }

    /// Every second: the clock the ring reads, and the session's own bookkeeping.
    private func tick(_ date: Date) {
        now = date
        app.tickFocus(now: date)
    }

    private func running(_ session: FocusSession) -> some View {
        let remaining = session.remaining(at: now)
        let progress = session.duration > 0 ? 1 - remaining / session.duration : 0
        let isRest = session.phase == .rest
        let task = session.taskID.flatMap { app.store.task(id: $0) }
        return VStack(spacing: 22) {
            header(session, isRest: isRest)
            ring(session, remaining: remaining, progress: progress, isRest: isRest)
            roundDots(session.rounds)
            mainControls(session, isRest: isRest)
            moreControls(task: task, isRest: isRest)
            totals(task: task)
            Spacer(minLength: 0)
        }
    }

    /// "Focus" in the tint, "Break" in green, and what's being focused on.
    private func header(_ session: FocusSession, isRest: Bool) -> some View {
        let phase: String = isRest ? "Break" : (session.isPaused && session.rounds > 0 ? "Ready for the next round" : "Focus")
        return VStack(spacing: 4) {
            Text(phase)
                .theoFont(.headline)
                .foregroundStyle(.tint)
                .contentTransition(.opacity)
                .animation(Motion.resolved(Motion.layout), value: phase)
                .tint(isRest ? Color.green : nil)
            Text(session.title)
                .theoFont(.title3, weight: .semibold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }

    /// The big ring fills in the tint as the phase runs (green for a break), around the time
    /// left in rounded figures that roll down second by second. Paused, the figures recede.
    private func ring(_ session: FocusSession, remaining: TimeInterval, progress: Double, isRest: Bool) -> some View {
        let seconds = Int(remaining.rounded(.up))
        let time = Self.clockText(remaining)
        let figures: Color = session.isPaused ? Color.secondary : Color.primary
        return ZStack {
            ProgressRing(progress: progress, lineWidth: 14)
            VStack(spacing: 4) {
                // A display figure sized for the fixed ring, like a glyph: it doesn't follow
                // the text size.
                Text(time)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(figures)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.resolved(Motion.tap), value: seconds)
                if session.isPaused {
                    Text("Paused")
                        .theoFont(.subheadline, weight: .medium)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .tint(isRest ? Color.green : nil)
        .frame(width: 260, height: 260)
        .animation(Motion.resolved(Motion.layout), value: session.isPaused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRest ? "Break" : "Focus")
        .accessibilityValue("\(time) left")
    }

    /// A dot for every focus round done; a new one pops in with a little bounce.
    private func roundDots(_ rounds: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<max(rounds, 1), id: \.self) { index in
                roundDot(done: index < rounds)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Motion.resolved(Motion.celebrate), value: rounds)
        .accessibilityLabel("\(rounds) rounds done")
    }

    @ViewBuilder
    private func roundDot(done: Bool) -> some View {
        if done {
            Circle()
                .fill(.tint)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 8, height: 8)
        }
    }

    /// Pause or go on (its symbol morphs between the two), and five minutes more.
    private func mainControls(_ session: FocusSession, isRest: Bool) -> some View {
        let paused = session.isPaused
        let title: String = paused ? (session.rounds > 0 && !isRest ? "Start" : "Resume") : "Pause"
        return HStack(spacing: 12) {
            Button {
                Motion.animate(Motion.tap) { togglePause(paused) }
            } label: {
                Label(title, systemImage: paused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 110)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button {
                Motion.animate(Motion.tap) { app.extendFocus(minutes: 5) }
            } label: {
                Label("+5 min", systemImage: "plus")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private func togglePause(_ paused: Bool) {
        if paused {
            app.resumeFocus()
        } else {
            app.pauseFocus()
        }
    }

    /// Skip Break while resting, Task Done, and Stop.
    private func moreControls(task: TaskItem?, isRest: Bool) -> some View {
        HStack(spacing: 12) {
            if isRest {
                Button("Skip Break") {
                    Motion.animate(Motion.layout) { app.skipBreak() }
                }
                .buttonStyle(.glass)
                .transition(Self.popIn)
            }
            if let task, !task.isDone, task.deletedAt == nil {
                Button {
                    // Stop first: the running stretch is booked before an ongoing task logs
                    // its finished copy, so the time lands on today's copy.
                    app.stopFocus()
                    if !task.isDone {
                        Motion.animate(Motion.list) { app.toggle(task) }
                    }
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
    }

    private var idle: some View {
        VStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 54))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("Focus for one Power Hour")
                .theoFont(.title3, weight: .semibold)
            Text("\(Int(app.focusMinutes)) minutes of focus, then a \(Int(app.breakMinutes))-minute break. Start it from a task to book the time on it.")
                .theoFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Motion.animate(Motion.layout) { app.startFocus(on: nil) }
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

    /// Today's focused Power Hours, and this task's, rolling as time is booked.
    private func totals(task: TaskItem?) -> some View {
        let phPerSecond = 1 / (PowerHours.minutesPerPH * 60)
        let today = FocusLog.seconds(on: now) * phPerSecond
        return VStack(spacing: 4) {
            Text("Today: \(PowerHours.format(today)) focused")
                .theoFont(.subheadline, weight: .medium)
                .rollingNumber(today)
            if let task {
                let spent = task.focusSeconds * phPerSecond
                Text(task.estimate > 0
                     ? "On this task: \(PowerHours.number(spent)) of \(PowerHours.format(task.estimate))"
                     : "On this task: \(PowerHours.format(spent))")
                    .theoFont(.footnote)
                    .foregroundStyle(.secondary)
                    .rollingNumber(spent)
            }
        }
        .padding(.top, 6)
    }

    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// "Focus 23:41" — shown on Today while a timer runs; tap opens it. A calm capsule washed in
/// the tint (green for a break), with the time rolling down second by second.
struct FocusPill: View {
    let session: FocusSession
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            pill(remaining: session.remaining(at: context.date))
                // With the sheet closed the pill is the only timer on screen: it ends a phase
                // that ran out, so it never sits at 0:00 and the break starts on time.
                .onChange(of: context.date) { _, date in
                    if !session.isPaused, session.remaining(at: date) <= 0 {
                        app.tickFocus()
                    }
                }
        }
    }

    private func pill(remaining: TimeInterval) -> some View {
        let isRest = session.phase == .rest
        let seconds = Int(remaining.rounded(.up))
        return Button {
            app.showFocus = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isRest ? "cup.and.saucer.fill" : "timer")
                    .foregroundStyle(.tint)
                Text(isRest ? "Break" : "Focus")
                Text(FocusView.clockText(remaining))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.resolved(Motion.tap), value: seconds)
            }
            .theoFont(.caption, weight: .semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(.tint)
                    .opacity(0.15)
            }
            .contentShape(Capsule())
            .tint(isRest ? Color.green : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRest ? "Break running" : "Focus running")
    }
}
