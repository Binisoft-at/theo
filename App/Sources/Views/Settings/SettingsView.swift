import SwiftUI
import UniformTypeIdentifiers
import TheoCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

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
    @State private var restoreCandidate: URL?
    @State private var pickBackupFile = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Text Size", selection: $textSizeRaw) {
                    ForEach(TextSizeChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                #if os(macOS)
                Text("⌘+ and ⌘− change it from anywhere, ⌘0 goes back to Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif

                VStack(alignment: .leading, spacing: 10) {
                    Text("Accent Color")
                    HStack(spacing: 12) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button {
                                accentRaw = choice.rawValue
                            } label: {
                                Circle()
                                    .fill(choice.color.gradient)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if accentRaw == choice.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("New day starts at", selection: $dayStartHour) {
                    ForEach(0...8, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
            } header: {
                Text("Daily Page")
            } footer: {
                Text("At the start of each day, unfinished tasks roll over to the new page and completed ones move to History — your Notes routine, automated.")
            }

            Section {
                Picker("Completed tasks", selection: $completedRaw) {
                    ForEach(CompletedMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Picker("New tasks go to", selection: $placementRaw) {
                    ForEach(NewTaskPlacement.allCases) { placement in
                        Text(placement.title).tag(placement.rawValue)
                    }
                }
                Picker("New tasks start with", selection: $defaultEstimate) {
                    Text("No estimate").tag(0.0)
                    ForEach([0.1, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                        Text(PowerHours.format(value)).tag(value)
                    }
                }
                Toggle("Show days carried over", isOn: $showAge)
                Toggle("Show notes preview", isOn: $showNotesPreview)
            } header: {
                Text("Tasks")
            } footer: {
                Text("Every new task gets this estimate unless you type or pick another one, or its group sets one. Remove it from a task any time.")
            }

            Section {
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
            } header: {
                Text("Day Review")
            } footer: {
                Text("Tap the ring on Today (or press ⌘9 on the Mac) to see what got done, during the day and after. The finished tasks export as CSV from there.")
            }

            Section {
                Picker("Focus", selection: $focusMinutes) {
                    ForEach([25, 45, 50, 60, 90], id: \.self) { minutes in
                        Text(minutes == 50 ? "50 min (1 PH)" : "\(minutes) min").tag(minutes)
                    }
                }
                Picker("Break", selection: $breakMinutes) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } header: {
                Text("Focus Timer")
            } footer: {
                Text("A Power Hour is 50 minutes of focused work. Focus time is booked on the task you start it from.")
            }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if app.sync.activeEvents > 0 {
                            ProgressView().controlSize(.small)
                        }
                        Text(app.sync.statusText)
                    }
                }
                if let error = app.sync.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Theo syncs through your private iCloud database, just like Notes. Nothing leaves your Apple account.")
            }

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
                    Label("Take the Tour", systemImage: "graduationcap")
                }
            } header: {
                Text("Help")
            } footer: {
                Text("A hands-on tour of adding, subtasks, priorities, gestures and undo, on a practice page.")
            }

            Section {
                LabeledContent("Last backup") {
                    Text(app.backups.lastBackup.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                }
                Button {
                    do {
                        try app.backups.backUpNow()
                        app.show("Backed up", symbol: "externaldrive.fill.badge.checkmark")
                    } catch {
                        app.show("Backup failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                    }
                } label: {
                    Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                }
                if let latest = app.backups.files.first {
                    ShareLink(item: latest) {
                        Label("Export Latest Backup…", systemImage: "square.and.arrow.up")
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
                        Label("Restore a Backup…", systemImage: "clock.arrow.circlepath")
                    }
                }
                Button {
                    pickBackupFile = true
                } label: {
                    Label("Restore from File…", systemImage: "doc.badge.arrow.up")
                }
                #if os(macOS)
                Button {
                    app.backups.revealInFinder()
                } label: {
                    Label("Show Backups in Finder", systemImage: "folder")
                }
                #endif
                if let error = app.backups.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Backups")
            } footer: {
                #if os(iOS)
                Text("Besides iCloud, Theo writes a full copy of all tasks and groups every day and keeps the last \(BackupManager.keep). They're in Files → On My iPhone → Theo → Backups, and in your iPhone's own backup. Restoring replaces everything, after one more copy of what's there now.")
                #else
                Text("Besides iCloud, Theo writes a full copy of all tasks and groups every day and keeps the last \(BackupManager.keep). Restoring replaces everything, after one more copy of what's there now.")
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

            Section("Data") {
                Button {
                    #if os(iOS)
                    app.showSettings = false
                    #endif
                    app.showImport = true
                } label: {
                    Label("Import from Notes…", systemImage: "square.and.arrow.down")
                }
            }

            Section {
                LabeledContent("Version", value: Self.version)
            } footer: {
                Text("Theo — your daily page, on steroids.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: dayStartHour) { _, _ in
            app.refreshDay()
        }
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
