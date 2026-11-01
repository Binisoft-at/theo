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
    @State private var showFilePicker = false

    private var lines: [NotesImport.Line] {
        NotesImport.parse(text, plainLinesAreHeadings: plainLinesAreHeadings)
    }

    var body: some View {
        let parsed = lines
        let headings = parsed.filter(\.isHeading).count
        let tasks = parsed.filter { !$0.isHeading && !(skipDone && $0.done) }.count

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
                    Text("In Notes: select all in your daily note, copy, and paste here. Checklist items become tasks, indented items become subtasks, “#” lines become groups and “##” lines subprojects inside them. “(0,5PH)” sets the estimate, “📅 2026-11-04” the deadline, “!!” the priority.")
                }

                Section {
                    Toggle("Lines without a checkbox are groups", isOn: $plainLinesAreHeadings)
                    Toggle("Skip completed items", isOn: $skipDone)
                }

                if !parsed.isEmpty {
                    Section("Preview · \(tasks) tasks · \(headings) groups") {
                        ForEach(parsed.prefix(60)) { line in
                            if line.isHeading {
                                Label(line.title, systemImage: line.level > 1 ? "folder.badge.plus" : "folder")
                                    .font(line.level > 1 ? .subheadline.weight(.semibold) : .headline)
                                    .padding(.leading, CGFloat(max(0, line.level - 1)) * 16)
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
                        let count = app.store.importLines(parsed, skipDone: skipDone)
                        app.show("Imported \(count) tasks", symbol: "square.and.arrow.down.fill")
                        app.go(.today)
                        dismiss()
                    }
                    .disabled(tasks == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }
}
