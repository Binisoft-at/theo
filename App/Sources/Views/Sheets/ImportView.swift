import SwiftUI
import UniformTypeIdentifiers
import TheoCore

/// Paste a daily note from Apple Notes (or any Markdown checklist) and turn it into tasks.
struct ImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var plainLinesAreHeadings = false
    @State private var skipDone = true
    @State private var replaceAll = false
    @State private var confirmReplace = false
    @State private var showFilePicker = false

    private var lines: [NotesImport.Line] {
        NotesImport.parse(text, plainLinesAreHeadings: plainLinesAreHeadings)
    }

    var body: some View {
        let parsed = lines
        let headings = parsed.filter(\.isHeading).count
        let tasks = parsed.filter { !$0.isHeading && !$0.isNote && !(skipDone && $0.done) }.count

        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 200)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose a Text or Markdown File…", systemImage: "doc.text")
                    }
                } header: {
                    Text("Paste your note")
                } footer: {
                    Text("In Notes: select all in your daily note, copy, and paste here. Checklist items become tasks, indented items become subtasks, “#” lines become groups and “##” lines subgroups inside them. “(0,5PH)” sets the estimate, “📅 2026-11-04” the deadline, “!!” the priority, “∞” makes a task ongoing, and a line starting with “>” is a note for the task above.")
                }

                Section {
                    Toggle("Lines without a checkbox are groups", isOn: $plainLinesAreHeadings)
                    Toggle("Skip completed items", isOn: $skipDone)
                    Toggle(isOn: $replaceAll) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replace everything")
                            Text("All current tasks and groups go to Recently Deleted first (kept for 30 days).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !parsed.isEmpty {
                    Section("Preview · \(tasks) tasks · \(headings) groups") {
                        ForEach(parsed.prefix(60)) { line in
                            if line.isHeading {
                                Label(line.title, systemImage: line.level > 1 ? "folder.badge.plus" : "folder")
                                    .font(line.level > 1 ? .subheadline.weight(.semibold) : .headline)
                                    .padding(.leading, CGFloat(max(0, line.level - 1)) * 16)
                            } else if line.isNote {
                                Text(line.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .padding(.leading, CGFloat(line.indent) * 20 + 26)
                            } else if !(skipDone && line.done) {
                                HStack(spacing: 8) {
                                    Image(systemName: line.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(line.done ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                                    Text(line.title)
                                }
                                .padding(.leading, CGFloat(line.indent) * 20)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let content = try? String(contentsOf: url, encoding: .utf8) { text = content }
            }
            .confirmationDialog("Replace everything?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace with \(tasks) Tasks", role: .destructive) { runImport(parsed, replacing: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every task and group you have now moves to Recently Deleted, then these are imported. You can undo right after, or restore from Recently Deleted for 30 days.")
            }
            .navigationTitle("Import from Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if replaceAll {
                            confirmReplace = true
                        } else {
                            runImport(parsed, replacing: false)
                        }
                    }
                    .disabled(tasks == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    private func runImport(_ lines: [NotesImport.Line], replacing: Bool) {
        let store = app.store
        let cleared = replacing ? store.clearEverything() : nil
        let count = store.importLines(lines, skipDone: skipDone)
        if let cleared {
            let imported = store.liveTasks()
            let groups = store.liveGroups()
            app.show("Replaced everything · \(count) tasks imported", symbol: "square.and.arrow.down.fill") {
                // Undo: the import goes, what was there before comes back.
                for task in imported { task.deletedAt = Date() }
                for group in groups { group.deletedAt = Date() }
                store.undoClear(cleared)
            }
        } else {
            app.show("Imported \(count) tasks", symbol: "square.and.arrow.down.fill")
        }
        app.go(.plan)
        dismiss()
    }
}
