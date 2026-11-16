import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import TheoCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// For the swatches' check: dark on bright colours, white on the others.
    @Environment(\.self) private var environment

    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue
    @AppStorage(Prefs.textSize) private var textSizeRaw = TextSizeChoice.platformDefault.rawValue
    @AppStorage(Prefs.dayStartHour) private var dayStartHour = 4
    @AppStorage(Prefs.showAge) private var showAge = true
    @AppStorage(Prefs.showNotesPreview) private var showNotesPreview = true
    @AppStorage(Prefs.completedMode) private var completedRaw = CompletedMode.bottom.rawValue
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue
    @AppStorage(Prefs.focusMinutes) private var focusMinutes = 50
    @AppStorage(Prefs.breakMinutes) private var breakMinutes = 10
    @AppStorage(Prefs.defaultEstimate) private var defaultEstimate = 0.25
    @AppStorage(Prefs.reviewPowerHours) private var reviewPowerHours = true
    @AppStorage(Prefs.reviewBreakdown) private var reviewBreakdown = true
    @AppStorage(Prefs.reviewComparison) private var reviewComparison = true
    @AppStorage(Prefs.reviewShare) private var reviewShare = true
    @AppStorage(Prefs.reviewTasks) private var reviewTasks = true
    @AppStorage(Prefs.reviewCompareDays) private var reviewCompareDays = 7
    /// "off" or "today": today's open count on the app icon (iPhone) or the Dock icon (Mac).
    /// The reminder scheduler reads the same key and does the counting.
    @AppStorage("badge.mode") private var badgeMode = "off"
    #if os(macOS)
    @AppStorage(HotKeyChoice.preferenceKey) private var hotKeyRaw = HotKeyChoice.standard.rawValue
    @AppStorage(HotKeyTarget.preferenceKey) private var hotKeyTargetRaw = HotKeyTarget.standard.rawValue
    #endif
    @State private var restoreCandidate: URL?
    @State private var pickBackupFile = false
    /// The badge is on but notifications (and so badges) are off for Theo in the system settings.
    @State private var badgeBlocked = false

    var body: some View {
        Form {
            appearanceSection
            dailyPageSection
            tasksSection
            #if os(macOS)
            quickAddSection
            #endif
            badgeSection
            reviewSection
            focusSection
            syncSection
            helpSection
            backupSection
            dataSection
            versionSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: dayStartHour) { _, _ in
            app.refreshDay()
        }
        .onChange(of: badgeMode) { _, mode in
            badgeModeChanged(mode)
        }
        #if os(macOS)
        .onChange(of: hotKeyRaw) { _, raw in
            GlobalHotKey.shared.apply(HotKeyChoice(rawValue: raw) ?? .standard)
        }
        #else
        .task {
            // Notifications may have been switched off in the Settings app since.
            if badgeMode == "today" {
                let blocked = await Self.badgesBlocked()
                Motion.animate(Motion.list) { badgeBlocked = blocked }
            }
        }
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #else
        .frame(width: 480)
        .frame(minHeight: 560)
        #endif
    }

    // MARK: - Sections
    //
    // Like the Settings app: every setting has its icon on a coloured tile in one column (the
    // colour says what it's about: orange for Today, teal for Power Hours, green for done ...);
    // actions (back up, restore, the tour) show the accent's symbol in the same column.

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearanceRaw) {
                ForEach(AppearanceChoice.allCases) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            } label: {
                SettingLabel("Theme", symbol: "circle.lefthalf.filled", color: .indigo)
            }
            .pickerStyle(.segmented)

            Picker(selection: $textSizeRaw) {
                ForEach(TextSizeChoice.allCases) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            } label: {
                SettingLabel("Text Size", symbol: "textformat.size", color: .blue)
            }

            accentRow
        } header: {
            Text("Appearance")
        } footer: {
            #if os(macOS)
            Text("⌘+ and ⌘− change the text size from anywhere, ⌘0 goes back to Large.")
                .theoFont(.footnote)
            #else
            Text("System follows the text size chosen in the Settings app.")
                .theoFont(.footnote)
            #endif
        }
    }

    /// The accent colours as swatches; the chosen one carries a check and a ring. On the Mac
    /// they sit to the right of the name, on iPhone and iPad in a row of their own.
    @ViewBuilder
    private var accentRow: some View {
        #if os(macOS)
        LabeledContent {
            accentSwatches
        } label: {
            SettingLabel("Accent Color", symbol: "paintpalette.fill", color: accent)
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            SettingLabel("Accent Color", symbol: "paintpalette.fill", color: accent)
            accentSwatches
        }
        .padding(.vertical, 4)
        #endif
    }

    private var accentSwatches: some View {
        HStack(spacing: Self.swatchSpacing) {
            ForEach(AccentChoice.allCases) { choice in
                swatch(choice)
            }
        }
        .animation(Motion.resolved(Motion.tap), value: accentRaw)
        .sensoryFeedback(.selection, trigger: accentRaw)
    }

    /// One colour: the check grows into it and a ring draws around it when it's picked. The
    /// check is dark on the bright ones (Notes Yellow), white on the others.
    private func swatch(_ choice: AccentChoice) -> some View {
        let isOn = accentRaw == choice.rawValue
        return Button {
            accentRaw = choice.rawValue
        } label: {
            Circle()
                .fill(choice.color.gradient)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: Self.swatchSize * 0.42, weight: .bold))
                        .foregroundStyle(choice.color.onFillForeground(in: environment))
                        .scaleEffect(isOn ? 1 : 0.4)
                        .opacity(isOn ? 1 : 0)
                }
                .padding(4)
                .overlay {
                    Circle()
                        .strokeBorder(choice.color, lineWidth: 2)
                        .scaleEffect(isOn ? 1 : 0.85)
                        .opacity(isOn ? 1 : 0)
                }
                #if os(iOS)
                .frame(maxWidth: .infinity, minHeight: 44)
                #endif
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var dailyPageSection: some View {
        Section {
            Picker(selection: $dayStartHour) {
                ForEach(0...8, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            } label: {
                SettingLabel("New day starts at", symbol: "sunrise.fill", color: Tint.today)
            }
        } header: {
            Text("Daily Page")
        } footer: {
            Text("A new day starts at this hour. Today shows what you plan for it; anything left open waits at the top of Today and in Plan.")
                .theoFont(.footnote)
        }
    }

    private var tasksSection: some View {
        Section {
            Picker(selection: $completedRaw) {
                ForEach(CompletedMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                SettingLabel("Completed tasks", symbol: "checkmark", color: Tint.done)
            }
            Picker(selection: $placementRaw) {
                ForEach(NewTaskPlacement.allCases) { placement in
                    Text(placement.title).tag(placement.rawValue)
                }
            } label: {
                SettingLabel("New tasks go to", symbol: "arrow.up.arrow.down", color: accent)
            }
            Picker(selection: $defaultEstimate) {
                Text("No estimate").tag(0.0)
                ForEach([0.1, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                    Text(PowerHours.format(value)).tag(value)
                }
            } label: {
                SettingLabel("New tasks start with", symbol: "timer", color: Tint.powerHours)
            }
            Toggle(isOn: $showAge) {
                SettingLabel("Show days carried over", symbol: "arrow.uturn.forward", color: .orange)
            }
            Toggle(isOn: $showNotesPreview) {
                SettingLabel("Show description under the title", symbol: "text.alignleft", color: .gray)
            }
        } header: {
            Text("Tasks")
        } footer: {
            Text("Every new task gets this estimate unless you type or pick another one, or its group sets one. Remove it from a task any time.")
                .theoFont(.footnote)
        }
    }

    #if os(macOS)
    private var quickAddSection: some View {
        Section {
            Picker(selection: $hotKeyRaw) {
                ForEach(HotKeyChoice.allCases) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            } label: {
                SettingLabel("Quick Add from any app", symbol: "keyboard", color: .gray)
            }
            Picker(selection: $hotKeyTargetRaw) {
                ForEach(HotKeyTarget.allCases) { target in
                    Text(target.title).tag(target.rawValue)
                }
            } label: {
                SettingLabel("Opens", symbol: "macwindow", color: .gray)
            }
            .disabled(hotKeyRaw == HotKeyChoice.off.rawValue)
        } header: {
            Text("Quick Add")
        } footer: {
            Text(quickAddFooter)
                .theoFont(.footnote)
        }
    }
    #endif

    private var badgeSection: some View {
        Section {
            Picker(selection: $badgeMode) {
                Text("Off").tag("off")
                Text("Open today").tag("today")
            } label: {
                // Today's colour: the badge counts what's still open on Today.
                SettingLabel("App icon badge", symbol: "app.badge", color: Tint.today)
            }
            if badgeBlocked {
                Text("Notifications are off for Theo, so the badge can't show. Turn them on in the Settings app → Notifications → Theo.")
                    .theoFont(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            #if os(iOS)
            Text("Shows on Theo's icon how many tasks on Today are still open. It uses notification permission; Theo asks when you turn it on.")
                .theoFont(.footnote)
            #else
            Text("Shows on Theo's Dock icon how many tasks on Today are still open.")
                .theoFont(.footnote)
            #endif
        }
    }

    private var reviewSection: some View {
        Section {
            // The same switches as the review's own Show menu, folded away.
            DisclosureGroup {
                Toggle("Power Hours worked", isOn: $reviewPowerHours)
                Toggle("What it went into", isOn: $reviewBreakdown)
                Toggle("Comparison with other days", isOn: $reviewComparison)
                Picker("Compare with", selection: $reviewCompareDays) {
                    ForEach([7, 14, 30], id: \.self) { days in
                        Text("\(days) days before").tag(days)
                    }
                }
                .disabled(!reviewComparison)
                Toggle("Share of the page done", isOn: $reviewShare)
                Toggle("Finished tasks", isOn: $reviewTasks)
            } label: {
                SettingLabel("What it shows", symbol: "chart.bar.fill", color: Tint.done)
            }
        } header: {
            Text("Day Review")
        } footer: {
            Text("Tap the ring on Today (or press ⌘9 on the Mac) to see what got done, during the day and after. Its Show menu has the same switches, and the finished tasks export as CSV from there.")
                .theoFont(.footnote)
        }
    }

    private var focusSection: some View {
        Section {
            Picker(selection: $focusMinutes) {
                ForEach([25, 45, 50, 60, 90], id: \.self) { minutes in
                    Text(minutes == 50 ? "50 min (1 PH)" : "\(minutes) min").tag(minutes)
                }
            } label: {
                SettingLabel("Focus", symbol: "timer", color: Tint.powerHours)
            }
            Picker(selection: $breakMinutes) {
                ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            } label: {
                SettingLabel("Break", symbol: "cup.and.saucer.fill", color: .mint)
            }
        } header: {
            Text("Focus Timer")
        } footer: {
            Text("A Power Hour is 50 minutes of focused work. Focus time is booked on the task you start it from.")
                .theoFont(.footnote)
        }
    }

    private var syncSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    if let storageStatus {
                        Text(storageStatus)
                            .foregroundStyle(Persistence.storeKind == .memory ? Color.red : Color.orange)
                    } else {
                        if app.sync.activeEvents > 0 {
                            ProgressView().controlSize(.small)
                        }
                        Text(app.sync.statusText)
                    }
                }
            } label: {
                SettingLabel("Status", symbol: "icloud.fill", color: .blue)
            }
            if let error = app.sync.lastError {
                Text(error)
                    .theoFont(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text("Theo syncs through your private iCloud database, just like Notes. Nothing leaves your Apple account.")
                .theoFont(.footnote)
        }
    }

    private var helpSection: some View {
        Section {
            Button {
                #if os(iOS)
                app.showSettings = false
                let model = app
                Task { @MainActor in
                    // Let the settings sheet finish closing before the tour covers the screen.
                    try? await Task.sleep(for: .milliseconds(450))
                    model.startTour()
                }
                #else
                app.startTour()
                #endif
            } label: {
                ActionLabel("Take the Tour", symbol: "graduationcap")
            }
            Button {
                showWhatsNew()
            } label: {
                ActionLabel("What's New", symbol: "sparkles")
            }
        } header: {
            Text("Help")
        } footer: {
            #if os(macOS)
            Text("A hands-on tour of adding, subtasks, priorities, gestures and undo, on a practice page. What's New shows only the latest additions. Keyboard shortcuts are listed at the bottom of the sidebar.")
                .theoFont(.footnote)
            #else
            Text("A hands-on tour of adding, subtasks, priorities, gestures and undo, on a practice page. What's New shows only the latest additions.")
                .theoFont(.footnote)
            #endif
        }
    }

    private var backupSection: some View {
        Section {
            LabeledContent {
                // Orange once it's more than two days old, so a stalled backup gets noticed.
                Text(app.backups.lastBackup.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                    .foregroundStyle(backupIsStale ? Color.orange : Color.secondary)
            } label: {
                SettingLabel("Last backup", symbol: "externaldrive.fill", color: .gray)
            }
            Button {
                do {
                    try app.backups.backUpNow()
                    app.show("Backed up", symbol: "externaldrive.fill.badge.checkmark")
                } catch {
                    app.show("Backup failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                }
            } label: {
                ActionLabel("Back Up Now", symbol: "externaldrive.badge.plus")
            }
            if let latest = app.backups.files.first {
                ShareLink(item: latest) {
                    ActionLabel("Export Latest Backup…", symbol: "square.and.arrow.up")
                }
            }
            if !app.backups.files.isEmpty {
                Menu {
                    ForEach(app.backups.files.prefix(14), id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Theo Backup ", with: "")) {
                            restoreCandidate = url
                        }
                    }
                } label: {
                    ActionLabel("Restore a Backup…", symbol: "clock.arrow.circlepath")
                }
            }
            Button {
                pickBackupFile = true
            } label: {
                ActionLabel("Restore from File…", symbol: "doc.badge.arrow.up")
            }
            #if os(macOS)
            Button {
                app.backups.revealInFinder()
            } label: {
                ActionLabel("Show Backups in Finder", symbol: "folder")
            }
            #endif
            if let error = app.backups.lastError {
                Text(error)
                    .theoFont(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Backups")
        } footer: {
            #if os(iOS)
            Text("Besides iCloud, Theo writes a full copy of all tasks and groups every day and keeps the last \(BackupManager.keep). They're in Files → On My iPhone → Theo → Backups, and in your iPhone's own backup. Restoring replaces everything, after one more copy of what's there now.")
                .theoFont(.footnote)
            #else
            Text("Besides iCloud, Theo writes a full copy of all tasks and groups every day and keeps the last \(BackupManager.keep). Restoring replaces everything, after one more copy of what's there now.")
                .theoFont(.footnote)
            #endif
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } }),
            titleVisibility: .visible,
            presenting: restoreCandidate
        ) { url in
            Button("Replace Everything with It", role: .destructive) { restore(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("All tasks, groups and views are replaced with “\(url.deletingPathExtension().lastPathComponent)”. What's there now is backed up first.")
        }
        .fileImporter(isPresented: $pickBackupFile, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { restoreCandidate = url }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button {
                #if os(iOS)
                app.showSettings = false
                #endif
                app.showImport = true
            } label: {
                ActionLabel("Import from Notes…", symbol: "square.and.arrow.down")
            }
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent("Version", value: Self.version)
        } footer: {
            Text("Theo — your daily page, on steroids.")
                .theoFont(.footnote)
        }
    }

    /// The chosen accent colour.
    private var accent: Color {
        (AccentChoice(rawValue: accentRaw) ?? .notes).color
    }

    #if os(macOS)
    private static let swatchSize: CGFloat = 18
    private static let swatchSpacing: CGFloat = 4
    #else
    private static let swatchSize: CGFloat = 28
    private static let swatchSpacing: CGFloat = 0
    #endif

    #if os(macOS)
    /// What the Quick Add shortcut does, for the setting picked.
    private var quickAddFooter: String {
        if HotKeyTarget(rawValue: hotKeyTargetRaw) == .window {
            return "Press it in any app: Theo comes to the front with the cursor in the bar at the bottom, ready for a new task. The menu bar icon works too."
        }
        return "Press it in any app: a small panel opens in front of it, and Theo stays in the background. Return adds the task, ⇧Return adds it and keeps the panel open for the next one, Esc closes it. Pasted lines become one task each. The menu bar icon works too."
    }
    #endif

    /// What Settings says instead of the sync status while tasks aren't stored the normal way.
    private var storageStatus: String? {
        guard !Persistence.isDemo else { return nil }
        switch Persistence.storeKind {
        case .cloud: return nil
        case .local: return AppIdentifiers.appCloudKitContainer != nil ? "Not syncing: this device only" : nil
        case .memory: return "Not saved: tasks couldn't be opened"
        }
    }

    private var backupIsStale: Bool {
        guard let last = app.backups.lastBackup else { return false }
        return Date().timeIntervalSince(last) > 2 * 86_400
    }

    /// Replays only the steps added in this version.
    private func showWhatsNew() {
        let steps = TutorialCatalog.steps(newerThan: TutorialCatalog.version - 1)
        guard !steps.isEmpty else {
            app.show("Nothing new to show in this version", symbol: "sparkles")
            return
        }
        #if os(iOS)
        app.showSettings = false
        let model = app
        Task { @MainActor in
            // Let the settings sheet finish closing before the tour covers the screen.
            try? await Task.sleep(for: .milliseconds(450))
            model.tour = TourRequest(steps: steps)
        }
        #else
        app.tour = TourRequest(steps: steps)
        #endif
    }

    /// The badge itself is set by the reminder scheduler on its next run. On iPhone, turning it
    /// on asks for notification permission first (the same request reminders make).
    private func badgeModeChanged(_ mode: String) {
        #if os(iOS)
        guard mode == "today" else {
            Motion.animate(Motion.list) { badgeBlocked = false }
            app.reminders?.scheduleSoon()
            return
        }
        let model = app
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let blocked = await Self.badgesBlocked()
            Motion.animate(Motion.list) { badgeBlocked = blocked }
            model.reminders?.scheduleSoon()
        }
        #else
        app.reminders?.scheduleSoon()
        #endif
    }

    #if os(iOS)
    private static func badgesBlocked() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().badgeSetting != .enabled
    }
    #endif

    private func restore(_ url: URL) {
        do {
            let count = try app.backups.restore(from: url)
            app.show("Restored \(count) tasks", symbol: "clock.arrow.circlepath")
        } catch {
            app.show("Couldn't restore: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return hour == 0 ? "Midnight" : date.formatted(date: .omitted, time: .shortened)
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// A setting's name with its icon on a coloured tile, the Settings app's way: the tiles stand in
/// one column, so the names line up.
private struct SettingLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            IconTile(symbol: symbol, color: color)
        }
    }
}

/// An action in Settings (back up, restore, the tour). On iPhone and iPad the accent's symbol
/// stands in the tiles' column, so its name lines up with the settings around it; the Mac's
/// buttons keep their usual look.
private struct ActionLabel: View {
    let title: LocalizedStringKey
    let symbol: String

    init(_ title: LocalizedStringKey, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        #if os(macOS)
        Label(title, systemImage: symbol)
        #else
        Label {
            Text(title)
        } icon: {
            IconTile(symbol: symbol, kind: .bare)
        }
        #endif
    }
}
