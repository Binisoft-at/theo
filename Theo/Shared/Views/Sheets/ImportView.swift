import SwiftUI

/// Paste a daily note from Apple Notes (or any Markdown checklist) and turn it into tasks.
struct ImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var plainLinesAreHeadings = false
    @State private var skipDone = true

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
                } header: {
                    Text("Paste your note")
                } footer: {
                    Text("In Notes: select all in your daily note, copy, and paste here. Checklist items become tasks, indented items become subtasks, and lines ending with “:” or starting with “#” become groups.")
                }

                Section {
                    Toggle("Lines without a checkbox are groups", isOn: $plainLinesAreHeadings)
                    Toggle("Skip completed items", isOn: $skipDone)
                }

                if !parsed.isEmpty {
                    Section("Preview · \(tasks) tasks · \(headings) groups") {
                        ForEach(parsed.prefix(60)) { line in
                            if line.isHeading {
                                Label(line.title, systemImage: "folder")
                                    .font(.headline)
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
