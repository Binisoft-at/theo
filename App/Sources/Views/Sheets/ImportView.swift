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

    /// The preview shows this many lines; the import takes them all.
    private static let previewLimit = 60

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
                        .theoFont(.body, design: .monospaced)
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

                optionsSection

                if !parsed.isEmpty {
                    previewSection(parsed, tasks: tasks, headings: headings)
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
            // A warning tap on iPhone before everything is replaced.
            #if os(iOS)
            .sensoryFeedback(.warning, trigger: confirmReplace) { _, shown in shown }
            #endif
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

    /// How the note is read, and whether it replaces what's there (red: it clears everything).
    private var optionsSection: some View {
        Section {
            Toggle(isOn: $plainLinesAreHeadings) {
                SheetRowLabel("Lines without a checkbox are groups", symbol: "folder")
            }
            Toggle(isOn: $skipDone) {
                SheetRowLabel("Skip completed items", symbol: "checkmark.circle", color: Tint.done)
            }
            Toggle(isOn: $replaceAll) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace everything")
                        Text("All current tasks and groups go to Recently Deleted first (kept for 30 days).")
                            .theoFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    SheetRowIcon("trash", color: Tint.delete)
                }
            }
            .tint(Tint.delete)
        }
    }

    /// What will be imported, with counts that roll as the note is edited.
    private func previewSection(_ parsed: [NotesImport.Line], tasks: Int, headings: Int) -> some View {
        Section {
            ForEach(parsed.prefix(Self.previewLimit)) { line in
                previewLine(line)
            }
        } header: {
            Text("Preview · \(Self.counted(tasks, "task")) · \(Self.counted(headings, "group"))")
                .contentTransition(.numericText())
                .animation(Motion.resolved(Motion.tap), value: tasks * 10_000 + headings)
        } footer: {
            if parsed.count > Self.previewLimit {
                Text("Showing the first \(Self.previewLimit) of \(parsed.count) lines. All of them are imported.")
            }
        }
    }

    /// "1 task", "3 tasks".
    private static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    /// One line as it will be imported: groups in bold with a folder, tasks with their
    /// checkbox, notes small under the task they belong to.
    @ViewBuilder
    private func previewLine(_ line: NotesImport.Line) -> some View {
        if line.isHeading {
            Label {
                Text(line.title)
            } icon: {
                Image(systemName: line.level > 1 ? "folder.badge.plus" : "folder")
                    .foregroundStyle(.secondary)
            }
            .theoFont(line.level > 1 ? .subheadline : .headline, weight: .semibold)
            .padding(.leading, CGFloat(max(0, line.level - 1)) * 16)
        } else if line.isNote {
            Text(line.title)
                .theoFont(.caption)
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
