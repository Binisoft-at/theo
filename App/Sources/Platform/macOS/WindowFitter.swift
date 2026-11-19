#if os(macOS)
import AppKit
import SwiftUI
import TheoCore

/// Keeps Theo's main window on its screen.
///
/// A Mac window can end up bigger than the screen it's on, the bar where tasks are added out of
/// sight below the screen's bottom edge: restored after working on a bigger display, left that
/// size when a display is unplugged or its resolution or the Dock changes, or pushed bigger by
/// something it shows. macOS leaves it that way. This puts the window back inside the part of
/// the screen windows may use (below the menu bar, above the Dock) whenever it ends up outside it
/// without the person putting it there: when it opens, when the displays or the Space change,
/// and after any resize or move not made with the mouse. A window the person drags or resizes
/// themselves is left alone, and so is full screen.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowFitterView {
        WindowFitterView()
    }

    func updateNSView(_ nsView: WindowFitterView, context: Context) {}
}

final class WindowFitterView: NSView {
    private weak var watched: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Bumped on every resize or move, so a burst of them (an animated resize) gets one check at
    /// its end.
    private var changeGeneration = 0
    /// When the person last moved the window with the mouse. A window they drag partly off the
    /// screen stays where they put it.
    private var lastMouseMove: Date?
    /// Set when the person starts dragging the window by its title bar, until the move ends.
    private var draggedByPerson = false
    /// Recent corrections. If something keeps pushing the window back out, it's left to win
    /// after a few, rather than the window jumping back and forth.
    private var corrections: [Date] = []

    /// Never in the way of a click: the view only watches its window.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window !== watched else { return }
        stopWatching()
        guard let window else { return }
        watched = window
        startWatching(window)
        WindowCheck.logState("attached", window)
        // SwiftUI applies the restored frame (or the default size) around the first layout.
        check(after: .milliseconds(300), reason: "open")
        check(after: .milliseconds(1500), reason: "open")
        check(after: .seconds(5), reason: "open")
        WindowCheck.startIfAsked(window: window)
    }

    private func startWatching(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowResized() }
            },
            // Moved without being resized: a sheet, the system or a restored position can put the
            // window's bottom below the Dock just the same.
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowMoved() }
            },
            // Posted when the person starts dragging the window.
            center.addObserver(forName: NSWindow.willMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    WindowCheck.log("will move")
                    self?.draggedByPerson = true
                }
            },
            center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(400), reason: "screen") }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(600), reason: "full screen") }
            },
            center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(400), reason: "Dock") }
            },
            // Back to Theo, or the window comes into view: a window that was out of sight when
            // Theo opened (on another Space, or Theo started in the background) gets checked then.
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(300), reason: "key") }
            },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.watched, window.occlusionState.contains(.visible) else { return }
                    self.check(after: .milliseconds(300), reason: "in view")
                }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(300), reason: "active") }
            },
            // A display plugged in or out, another resolution, the Dock bigger or moved.
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(600), reason: "displays") }
            },
        ]
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .milliseconds(400), reason: "Space") }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(after: .seconds(2), reason: "wake") }
            },
        ]
    }

    private func stopWatching() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        workspaceObservers = []
        watched = nil
    }

    private func windowResized() {
        guard let window = watched else { return }
        WindowCheck.log("resized to \(WindowCheck.describe(window.frame))")
        // A size the person drags is theirs.
        guard !window.inLiveResize else { return }
        checkWhenSettled(reason: "resize")
    }

    private func windowMoved() {
        guard let window = watched else { return }
        WindowCheck.log("moved to \(WindowCheck.describe(window.frame))")
        // A place the person drags the window to is theirs.
        let buttonDown = NSEvent.pressedMouseButtons != 0
        if draggedByPerson || buttonDown {
            lastMouseMove = Date()
            if !buttonDown { draggedByPerson = false }
            return
        }
        checkWhenSettled(reason: "move")
    }

    /// One check once a burst of resizes or moves is over, unless the person just moved the
    /// window with the mouse.
    private func checkWhenSettled(reason: String) {
        changeGeneration += 1
        let generation = changeGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.changeGeneration == generation else { return }
            if let moved = self.lastMouseMove, Date().timeIntervalSince(moved) < 1.5 { return }
            self.fit(reason: reason)
        }
    }

    private func check(after delay: Duration, reason: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.fit(reason: reason)
        }
    }

    private func fit(reason: String) {
        guard let window = watched else { return }
        guard window.isVisible, !window.isMiniaturized, !window.styleMask.contains(.fullScreen),
              !window.inLiveResize,
              // A window being dragged: wait for the next check.
              NSEvent.pressedMouseButtons == 0,
              let screen = window.screen ?? NSScreen.main else {
            WindowCheck.log("check (\(reason)) not now: visible \(window.isVisible), in Dock \(window.isMiniaturized), full screen \(window.styleMask.contains(.fullScreen)), resizing \(window.inLiveResize), mouse \(NSEvent.pressedMouseButtons)")
            return
        }
        let visible = screen.visibleFrame
        let frame = window.frame
        guard !WindowFit.fits(frame, in: visible) else {
            if reason == "open" { WindowCheck.logState("fits (open)", window) }
            return
        }
        let now = Date()
        corrections.removeAll { now.timeIntervalSince($0) > 5 }
        guard corrections.count < 3 else {
            WindowCheck.log("fit (\(reason)) skipped: the window keeps being pushed out")
            return
        }
        corrections.append(now)
        // From now on the window can be made as small as the screen, whatever its content asked for.
        let room = window.contentRect(forFrameRect: visible).size
        let minimum = window.contentMinSize
        if minimum.width > room.width || minimum.height > room.height {
            window.contentMinSize = NSSize(width: min(minimum.width, room.width), height: min(minimum.height, room.height))
        }
        let target = WindowFit.fitted(frame, in: visible)
        WindowCheck.log("fit (\(reason)): \(WindowCheck.describe(frame)) to \(WindowCheck.describe(target)), screen \(WindowCheck.describe(visible))")
        window.setFrame(target, display: true, animate: false)
        // Whatever pushes the window back out shows up here.
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .milliseconds(700))
            if let window { WindowCheck.logState("after fit (\(reason))", window) }
        }
    }
}

/// `-TheoWindowCheck` (CI): goes through the pages, the details column, the sheets and the
/// largest text size, and prints the window's frame and the smallest size it allows at each
/// step, so whatever pushes the window bigger shows up. Then it hangs the window off the bottom
/// of the screen and zooms it, to see `WindowFitter` put it back. `-TheoWindowLog` prints only
/// the fitter's own moves. Both write to standard error, starting each line with "WINDOW".
@MainActor
enum WindowCheck {
    private static var started = false

    private static let isLogging: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-TheoWindowLog") || args.contains("-TheoWindowCheck")
    }()

    static func log(_ line: @autoclosure () -> String) {
        guard isLogging else { return }
        FileHandle.standardError.write(Data(("WINDOW " + line() + "\n").utf8))
    }

    static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }

    static func describe(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    /// The window's frame, its screen and every size limit on it, including the one its content
    /// asks for (`fittingSize`), which `contentMinSize` doesn't show.
    static func logState(_ label: String, _ window: NSWindow) {
        guard isLogging else { return }
        let screen = window.screen
        let screens = NSScreen.screens.map { describe($0.visibleFrame) }.joined(separator: " | ")
        let fitting = window.contentView.map { describe($0.fittingSize) } ?? "none"
        log("\(label): frame \(describe(window.frame)), screen \(screen.map { describe($0.visibleFrame) } ?? "none") of [\(screens)], content min \(describe(window.contentMinSize)), min \(describe(window.minSize)), max \(describe(window.maxSize)), content needs \(fitting), zoomed \(window.isZoomed), visible \(window.isVisible), on this Space \(window.isOnActiveSpace), autosave \"\(window.frameAutosaveName)\"")
    }

    static func startIfAsked(window: NSWindow) {
        guard !started, ProcessInfo.processInfo.arguments.contains("-TheoWindowCheck"), let app = AppModel.shared else { return }
        started = true
        Task { @MainActor in
            await run(window: window, app: app)
        }
    }

    private static func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private static func run(window: NSWindow, app: AppModel) async {
        await pause(3000)
        let visible = window.screen?.visibleFrame ?? .zero
        log("screen \(describe(visible)), at launch \(describe(window.frame)), content min \(describe(window.contentMinSize))")

        app.showInspector = false
        await pause(1000)
        await measure("today without details", window)
        app.showInspector = true
        await pause(1000)
        let pages: [(String, SidebarItem)] = [
            ("today", .today), ("plan", .plan), ("overview", .overview), ("all tasks", .allTasks),
            ("upcoming", .upcoming), ("matrix", .matrix), ("quick entry", .quickEntry),
            ("priority", .priority), ("history", .history), ("recently deleted", .trash),
        ]
        for (name, item) in pages {
            app.go(item)
            await pause(1200)
            await measure(name, window)
        }
        app.go(.today)
        await pause(800)

        UserDefaults.standard.set(true, forKey: "sidebar.showShortcuts")
        await pause(1000)
        await measure("today, keyboard shortcuts open", window)

        if let task = app.store.liveTasks().first(where: { !$0.isDone }) {
            app.showDetails(task)
            await pause(1200)
            await measure("today, a task's details", window)
            app.detailTask = task
            await pause(1500)
            logSheet("task sheet", window)
            app.detailTask = nil
            await pause(1000)
        }
        app.startTour()
        await pause(2000)
        logSheet("tour", window)
        app.finishTour()
        await pause(1000)
        app.reviewDay = DayRef(start: app.dayStart)
        await pause(1500)
        logSheet("day review", window)
        app.reviewDay = nil
        await pause(1000)
        app.groupEditor = .new
        await pause(1500)
        logSheet("new group", window)
        app.groupEditor = nil
        await pause(1000)
        log("sheets closed: \(describe(window.frame))")

        let size = UserDefaults.standard.string(forKey: Prefs.textSize)
        UserDefaults.standard.set(TextSizeChoice.huge.rawValue, forKey: Prefs.textSize)
        await pause(1200)
        log("huge text set: \(describe(window.frame))")
        await measure("today, huge text", window)
        app.go(.plan)
        await pause(1200)
        await measure("plan, huge text", window)
        UserDefaults.standard.set(size, forKey: Prefs.textSize)
        app.go(.today)
        await pause(1200)

        // As after a bigger display is unplugged: taller than the screen, hanging off its bottom.
        let tall = NSRect(x: window.frame.minX, y: visible.minY - 400, width: window.frame.width, height: visible.height + 300)
        window.setFrame(tall, display: true)
        log("made too tall: \(describe(window.frame))")
        await pause(2000)
        log("after the fitter: \(describe(window.frame)), inside the screen: \(WindowFit.fits(window.frame, in: visible))")

        window.zoom(nil)
        await pause(2000)
        log("zoomed: \(describe(window.frame)), inside the screen: \(WindowFit.fits(window.frame, in: visible))")
        window.zoom(nil)
        await pause(2000)
        log("zoomed back: \(describe(window.frame)), inside the screen: \(WindowFit.fits(window.frame, in: visible))")

        // Moved down without a resize, its bottom below the Dock.
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: visible.minY - 200))
        log("moved down: \(describe(window.frame))")
        await pause(1500)
        log("after a move: \(describe(window.frame)), inside the screen: \(WindowFit.fits(window.frame, in: visible))")
        log("check done")
    }

    /// The window made small, to see how small the page lets it get, then put back.
    private static func measure(_ label: String, _ window: NSWindow) async {
        let normal = window.frame
        window.setFrame(NSRect(x: normal.minX, y: normal.maxY - 320, width: 520, height: 320), display: true)
        await pause(1000)
        let smallest = window.frame.size
        let minimum = window.contentMinSize
        window.setFrame(normal, display: true)
        await pause(600)
        log("\(label): \(describe(window.frame)), smallest \(describe(smallest)), content min \(describe(minimum))")
    }

    private static func logSheet(_ label: String, _ window: NSWindow) {
        let sheet = window.attachedSheet.map { describe($0.frame) } ?? "none"
        log("\(label): window \(describe(window.frame)), sheet \(sheet)")
    }
}
#endif
