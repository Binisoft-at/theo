import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue
    @AppStorage(Prefs.dayStartHour) private var dayStartHour = 4
    @AppStorage(Prefs.showAge) private var showAge = true
    @AppStorage(Prefs.showNotesPreview) private var showNotesPreview = true
    @AppStorage(Prefs.completedMode) private var completedRaw = CompletedMode.bottom.rawValue
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.segmented)

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

            Section("Tasks") {
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
                Toggle("Show days carried over", isOn: $showAge)
                Toggle("Show notes preview", isOn: $showNotesPreview)
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
