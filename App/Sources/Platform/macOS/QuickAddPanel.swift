#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI
import TheoCore

/// The Quick Add shortcut's floating panel, like Spotlight: it opens in front of whatever app is
/// active without bringing Theo (or its window) forward, takes a task, and goes away again.
///
/// - Return adds and closes; ⇧Return (or ⌘Return) adds and stays open for the next one.
/// - Esc, the shortcut again, or a click elsewhere closes it. Esc forgets the text; the other
///   two keep it for the next time (for a while).
/// - Pasted lines become one task each, every line read the way the menu bar reads one.
/// - Works while the main window is closed (Theo only in the menu bar).
@MainActor
final class QuickAddPanel {
    static let shared = QuickAddPanel()

    /// Why the panel closes: Esc and an add forget the text; a click elsewhere or the shortcut
    /// keeps it.
    enum CloseReason {
        case cancel, added, away
    }

    /// A task the panel added, and whether it went on today's plan.
    struct Added {
        let task: TaskItem
        let planned: Bool
    }

    /// Text left behind by a click elsewhere comes back for this long.
    private static let draftLifetime: TimeInterval = 10 * 60

    let state: QuickAddState
    private var panel: QuickAddWindow?
    private var host: NSView?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var closedAt: Date?

    private init() {
        state = QuickAddState()
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// The shortcut: opens the panel, or closes it when it's already open.
    func toggle() {
        if isShown {
            close(.away)
        } else {
            show()
        }
    }

    func show() {
        guard let app = AppModel.shared else {
            GlobalHotKey.focusComposer()
            return
        }
        // Theo stays in the background, so the new-day check it does when it comes forward
        // happens here: "tomorrow" must mean the day after the real today.
        app.refreshDay()
        if let closedAt, Date().timeIntervalSince(closedAt) > Self.draftLifetime {
            state.text = ""
        }
        state.confirmation = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = Self.appearance
        host?.removeFromSuperview()
        // A fresh SwiftUI view each time, so the field takes the cursor as it appears.
        let hosting = NSHostingView(rootView: QuickAddPanelRoot(app: app, state: state))
        let fitting = hosting.fittingSize.height
        let height = fitting > 40 && fitting < 800 ? ceil(fitting) : 120
        // From here on the panel follows the content's height itself (`fit(height:)`), keeping
        // its top edge where it is.
        hosting.sizingOptions = []
        place(panel, height: height)
        if let content = panel.contentView {
            hosting.frame = content.bounds
            hosting.autoresizingMask = [.width, .height]
            content.addSubview(hosting)
        }
        host = hosting
        // Key without activating Theo: the app in front stays in front.
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        startWatching(panel)
    }

    func close(_ reason: CloseReason) {
        stopWatching()
        guard let panel, panel.isVisible else { return }
        switch reason {
        case .cancel, .added:
            state.text = ""
        case .away:
            break
        }
        closedAt = Date()
        state.confirmation = nil
        panel.orderOut(nil)
        host?.removeFromSuperview()
        host = nil
    }

    /// The content's height changed (a pasted list, the line under the field): grows or shrinks
    /// downward, like Spotlight, so the field stays where it was.
    func fit(height: CGFloat) {
        guard let panel, panel.isVisible, height > 20 else { return }
        let target = ceil(height)
        let frame = panel.frame
        guard abs(frame.height - target) > 0.5 else { return }
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - target, width: frame.width, height: target), display: true)
        panel.invalidateShadow()
    }

    // MARK: - Window

    private func makePanel() -> QuickAddWindow {
        let panel = QuickAddWindow(
            contentRect: NSRect(x: 0, y: 0, width: QuickAddLayout.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Add"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        // Frosted like Spotlight; the mask rounds it, and the shadow follows the mask.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = QuickAddLayout.roundedMask(radius: QuickAddLayout.cornerRadius)
        panel.contentView = background
        return panel
    }

    /// Centred in the upper part of the screen the mouse is on.
    private func place(_ panel: NSPanel, height: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = visible.maxY - (visible.height * 0.22).rounded()
        let x = (visible.midX - QuickAddLayout.width / 2).rounded()
        panel.setFrame(NSRect(x: x, y: top - height, width: QuickAddLayout.width, height: height), display: false)
    }

    /// Theo's own Light / Dark setting (nil follows the system).
    private static var appearance: NSAppearance? {
        let choice = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.appearance) ?? "") ?? .system
        switch choice {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Keys

    private func startWatching(_ panel: NSPanel) {
        stopWatching()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }
        // A click in another app or another Theo window.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close(.away)
            }
        }
    }

    private func stopWatching() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// Keys typed in the panel, seen before the field and the menu bar get them (⌘Return would
    /// otherwise be the Task menu's Mark as Done). True when the panel took the key.
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel else { return false }
        // Typing through an input method (Japanese, Chinese, ...): Return and Esc are its own.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_Escape:
            close(.cancel)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // ⌥Return types a line break: one task per line.
            if flags.contains(.option) { return false }
            submit(keepOpen: flags.contains(.shift) || flags.contains(.command))
            return true
        case kVK_Tab:
            // There's nowhere else to go: Tab would only take the cursor out of the field.
            return true
        case kVK_Delete where flags.contains(.command):
            // Deletes back to the start of the line, as in any text field (never the Task
            // menu's Delete, which acts on the main window's selection).
            _ = perform(#selector(NSStandardKeyBindingResponding.deleteToBeginningOfLine(_:)))
            return true
        default:
            break
        }
        guard flags.contains(.command) else { return false }
        return handleCommand(event, shift: flags.contains(.shift))
    }

    /// ⌘ shortcuts: editing ones go to the field, ⌘W and ⌘. close, ⌘Q quits; every other one
    /// belongs to Theo's window and does nothing here.
    private func handleCommand(_ event: NSEvent, shift: Bool) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "w", ".":
            close(.cancel)
            return true
        case "q":
            return false
        case "v":
            _ = perform(#selector(NSText.paste(_:)))
            return true
        case "c":
            _ = perform(#selector(NSText.copy(_:)))
            return true
        case "x":
            _ = perform(#selector(NSText.cut(_:)))
            return true
        case "a":
            _ = perform(#selector(NSText.selectAll(_:)))
            return true
        case "z":
            _ = perform(shift ? Selector(("redo:")) : Selector(("undo:")))
            return true
        default:
            // ⌘← ⌘→ ⌘↑ ⌘↓ (function keys) move the cursor in the field.
            if let scalar = key.unicodeScalars.first, (0xF700...0xF8FF).contains(scalar.value) { return false }
            return true
        }
    }

    /// Sends an editing action up from the field.
    private func perform(_ action: Selector) -> Bool {
        panel?.firstResponder?.tryToPerform(action, with: nil) ?? false
    }

    // MARK: - Adding

    /// Return: adds what's typed. Kept open, the field empties and says what was added.
    private func submit(keepOpen: Bool) {
        let raw = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            // Return in an empty panel just closes it.
            if !keepOpen { close(.cancel) }
            return
        }
        guard let app = AppModel.shared else { return }
        // The panel may have been open across the start of a new day.
        app.refreshDay()
        let added = addTasks(raw, app: app)
        guard !added.isEmpty else {
            // Only shortcuts ("!! #home") and no title yet: nothing to add.
            NSSound.beep()
            return
        }
        state.text = ""
        if keepOpen {
            state.confirm(confirmation(for: added, app: app))
        } else {
            close(.added)
        }
    }

    /// One task per line, each added the way the menu bar adds one: parsed on the logical day
    /// with the groups, filed by `@group` (else Quick Entry) at the place Settings says, and on
    /// today's plan unless its deadline is on a later day. The store saves each one.
    private func addTasks(_ raw: String, app: AppModel) -> [Added] {
        let store = app.store
        let today = app.dayStart
        let refs = store.liveGroups().map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName, parentID: $0.parentUUID) }
        let placement = NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom
        let lines = QuickAddCapture.lines(raw)
        // "Top of Section" puts each task above the one before: a list goes in last line first,
        // so it still reads in its order.
        let flipped = lines.count > 1 && placement == .top
        let ordered: [String] = flipped ? Array(lines.reversed()) : lines
        var added: [Added] = []
        // The new lines glide into any list that's open in Theo's window.
        Motion.animate(Motion.list) {
            for line in ordered {
                let entry = QuickParser.parse(line, groups: refs, now: today)
                guard !entry.title.isEmpty else { continue }
                let task = store.addTask(entry, defaultGroupID: nil, placement: placement)
                // Read from the task, so a repeat's first date counts.
                let planned = QuickAddCapture.plansToday(due: task.dueDate, today: today)
                if planned { store.plan([task], for: today) }
                added.append(Added(task: task, planned: planned))
            }
        }
        return flipped ? Array(added.reversed()) : added
    }

    /// "Added to Work · due Friday · !!" (read back from the task, worded as the composer and
    /// the menu bar say it) plus "· on today" when it went on today's plan; "Added 3 tasks" for
    /// a list.
    private func confirmation(for added: [Added], app: AppModel) -> String {
        guard added.count == 1, let first = added.first else {
            let planned = added.filter(\.planned).count
            let onToday = planned == 0 ? "" : (planned == added.count ? " · on today" : " · \(planned) on today")
            return "Added \(added.count) tasks" + onToday
        }
        let task = first.task
        let group = task.group.flatMap { $0.deletedAt == nil ? $0 : nil }
        let understood = CaptureSummary.describe(
            groupName: group?.displayName ?? "Quick Entry",
            due: task.dueDate,
            dueHasTime: task.dueHasTime,
            today: app.dayStart,
            priority: task.priority,
            estimate: task.estimate,
            defaultEstimate: app.store.traits(of: group).estimate ?? PowerHours.defaultForNewTasks,
            recurrence: task.recurrence,
            ongoing: task.isOngoing
        )
        return "Added to " + understood + (first.planned ? " · on today" : "")
    }
}

/// The panel's window: borderless and non-activating, yet it takes the keyboard. It never
/// becomes the main window, so `MainWindow.isVisible` doesn't count it.
final class QuickAddWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// What the panel shows: the text being typed (kept while the panel is away, see
/// `QuickAddPanel.CloseReason`) and the "Added to …" line.
@MainActor
@Observable
final class QuickAddState {
    var text = ""
    var confirmation: String?
    /// Counts the adds that keep the panel open: the + and the check bounce with each one.
    private(set) var addedCount = 0
    @ObservationIgnored private var confirmationID = UUID()

    /// "Added to Work · due Friday · !!" under the field for a moment.
    func confirm(_ message: String) {
        let id = UUID()
        confirmationID = id
        confirmation = message
        addedCount += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, self.confirmationID == id else { return }
            self.confirmation = nil
        }
    }
}

/// Reading what's typed in the panel: the menu bar's rules, line by line.
enum QuickAddCapture {
    /// The text as one line, or for a pasted list each line that isn't ticked off (with the
    /// lines under a ticked one), list markers ("- ", "• ", "[ ] ") dropped, as the composer
    /// reads a pasted list.
    static func lines(_ raw: String) -> [String] {
        guard raw.contains(where: \.isNewline) else { return [raw] }
        var result: [String] = []
        var skipBelow: Int?
        for line in Composer.lines(raw) {
            if let level = skipBelow {
                if line.level > level { continue }
                skipBelow = nil
            }
            if line.done {
                skipBelow = line.level
                continue
            }
            result.append(line.title)
        }
        return result
    }

    /// The menu bar's rule: on today's plan unless the deadline is on a later day.
    static func plansToday(due: Date?, today: Date) -> Bool {
        due.map { DateText.dayDelta($0, today: today) <= 0 } ?? true
    }
}

enum QuickAddLayout {
    static let width: CGFloat = 560
    static let cornerRadius: CGFloat = 24
    /// The content's distance from the panel's sides.
    static let inset: CGFloat = 20
    /// The icons' column (at standard text size), so the field's text and the line under it
    /// start at the same place.
    static let iconColumn: CGFloat = 22
    static let gap: CGFloat = 12

    /// A stretchable rounded rectangle for the frosted background's mask.
    @MainActor
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The panel's SwiftUI content with what the main window gives its views: the model, the
/// store, Theo's text size and accent colour.
private struct QuickAddPanelRoot: View {
    let app: AppModel
    let state: QuickAddState

    var body: some View {
        QuickAddPanelView(state: state)
            .environment(app)
            .modelContainer(app.container)
            .theoTextSize(TextSizeChoice.current)
            .tint((AccentChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.accent) ?? "") ?? .notes).color)
    }
}

/// The field and, under it, what will be understood (or what was just added). The icons sit in
/// one column, so the field's text and the line under it start at the same place; the line under
/// the field changes with a soft blur, and the + (and the check) bounce with each add that keeps
/// the panel open.
private struct QuickAddPanelView: View {
    @Bindable var state: QuickAddState
    @Environment(AppModel.self) private var app
    @Environment(\.textScale) private var textScale
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @FocusState private var focused: Bool

    /// What the line under the field shows.
    private enum FooterKind: Equatable {
        case hint, preview, added
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            Divider()
                .padding(.horizontal, QuickAddLayout.inset)
            footerLine
        }
        .frame(width: QuickAddLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            RoundedRectangle(cornerRadius: QuickAddLayout.cornerRadius, style: .circular)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            Task { @MainActor in
                QuickAddPanel.shared.fit(height: newHeight)
            }
        }
        .onAppear {
            focused = true
            Task { @MainActor in
                // Again once the panel is key, in case it wasn't yet.
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
        }
    }

    /// The icons' column at Theo's text size.
    private var iconColumn: CGFloat { (QuickAddLayout.iconColumn * textScale).rounded() }

    private var field: some View {
        HStack(alignment: .firstTextBaseline, spacing: QuickAddLayout.gap) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: state.addedCount)
                .frame(width: iconColumn)
            TextField("New task — try “Report bis Freitag !! #work”", text: $state.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .accessibilityLabel("New task")
        }
        .theoFont(.title2)
        .padding(.horizontal, QuickAddLayout.inset)
        .padding(.vertical, 16)
    }

    /// The line under the field. What it shows crosses over in place (a soft blur) instead of
    /// stacking up, so the panel keeps its height.
    private var footerLine: some View {
        let animation = Motion.resolved(Motion.tap)
        return ZStack(alignment: .leading) {
            footer
        }
        .theoFont(.callout)
        .lineLimit(1)
        .contentTransition(.opacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, QuickAddLayout.inset)
        .padding(.vertical, 12)
        .animation(animation, value: footerKind)
        .animation(animation, value: state.addedCount)
    }

    private var footerKind: FooterKind {
        if !trimmed.isEmpty { return .preview }
        return state.confirmation == nil ? .hint : .added
    }

    private var trimmed: String {
        state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groupRefs: [QuickParser.GroupRef] {
        groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName, parentID: $0.parentUUID) }
    }

    @ViewBuilder
    private var footer: some View {
        if !trimmed.isEmpty {
            preview(QuickAddCapture.lines(trimmed))
                .transition(.blurReplace)
        } else if let message = state.confirmation {
            row("checkmark.circle.fill", .tint, Text(message).foregroundStyle(.secondary))
                .symbolEffect(.bounce, value: state.addedCount)
                .transition(.blurReplace)
        } else {
            row("keyboard", .tertiary, Text("Return adds · ⇧Return adds another · Esc cancels").foregroundStyle(.tertiary))
                .transition(.blurReplace)
        }
    }

    @ViewBuilder
    private func preview(_ lines: [String]) -> some View {
        if lines.isEmpty {
            row("checkmark.circle", .secondary, Text("Every line is ticked off: nothing to add").foregroundStyle(.secondary))
        } else if lines.count == 1 {
            singlePreview(lines[0])
        } else {
            listPreview(lines)
        }
    }

    /// "Report  →  Work · due Friday · !! · #work · ☀ on today", in the group's colour.
    private func singlePreview(_ line: String) -> some View {
        let entry = QuickParser.parse(line, groups: groupRefs, now: app.dayStart).withFirstOccurrence(today: app.dayStart)
        let group = groups.first { $0.uuid == entry.groupID }
        let symbol = group?.symbol ?? "tray.and.arrow.down"
        let color: Color = group?.color.color ?? .secondary
        return row(symbol, color, previewText(entry, group: group))
    }

    private func previewText(_ entry: ParsedEntry, group: TaskGroup?) -> Text {
        guard !entry.title.isEmpty else {
            return Text("Type what to do; “!!”, “#tag”, “@group” and dates are read from the text").foregroundStyle(.secondary)
        }
        var detail = CaptureSummary.describe(
            groupName: group?.displayName ?? "Quick Entry",
            due: entry.due,
            dueHasTime: entry.dueHasTime,
            today: app.dayStart,
            priority: entry.priority,
            estimate: entry.estimate,
            defaultEstimate: app.store.traits(of: group).estimate ?? PowerHours.defaultForNewTasks,
            recurrence: entry.recurrence,
            ongoing: entry.ongoing
        )
        for tag in entry.tags {
            detail += " · #" + tag
        }
        let title = Text(entry.title).fontWeight(.semibold).foregroundStyle(Color.primary)
        let rest = Text("  →  " + detail).foregroundStyle(Color.secondary)
        guard QuickAddCapture.plansToday(due: entry.due, today: app.dayStart) else {
            return Text("\(title)\(rest)")
        }
        return Text("\(title)\(rest)\(onToday(nil))")
    }

    /// "3 tasks  →  one per line · ☀ 2 on today".
    private func listPreview(_ lines: [String]) -> some View {
        let refs = groupRefs
        let entries = lines
            .map { QuickParser.parse($0, groups: refs, now: app.dayStart).withFirstOccurrence(today: app.dayStart) }
            .filter { !$0.title.isEmpty }
        let planned = entries.filter { QuickAddCapture.plansToday(due: $0.due, today: app.dayStart) }.count
        let label: String = entries.count == 1 ? "1 task" : "\(entries.count) tasks"
        let count = Text(label).fontWeight(.semibold).foregroundStyle(Color.primary)
        let rest = Text("  →  one per line").foregroundStyle(Color.secondary)
        let text: Text
        if planned == 0 {
            text = Text("\(count)\(rest)")
        } else {
            text = Text("\(count)\(rest)\(onToday(planned == entries.count ? nil : planned))")
        }
        return row("list.bullet", .tint, text)
    }

    /// " · ☀ on today" (or " · ☀ 2 on today"), in Today's orange.
    private func onToday(_ count: Int?) -> Text {
        let words: String = count.map { "\($0) on today" } ?? "on today"
        return Text(" · \(Image(systemName: "sun.max.fill")) \(words)").foregroundStyle(Tint.today)
    }

    /// An icon in the column under the field's +, and the words lined up with the field's text.
    private func row<S: ShapeStyle>(_ symbol: String, _ style: S, _ text: Text) -> some View {
        HStack(spacing: QuickAddLayout.gap) {
            Image(systemName: symbol)
                .foregroundStyle(style)
                .frame(width: iconColumn)
            text
                .truncationMode(.tail)
        }
    }
}
#endif
