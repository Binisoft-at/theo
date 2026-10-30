import SwiftUI
import SwiftData
import TheoCore

/// Floating Liquid Glass field at the bottom of a page. Type, hit Return, keep typing.
/// Understands `!!`, `#tag`, `@group` and natural dates, and previews what it parsed.
struct QuickEntryBar: View {
    /// Where new tasks go when no `@group` is typed (nil = Quick Entry).
    var defaultGroupID: UUID?
    var placeholder = "Quick entry"

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue

    @State private var text = ""
    @State private var disabled: QuickParser.Options = []
    @State private var addedCount = 0
    @FocusState private var focused: Bool

    private var options: QuickParser.Options { QuickParser.Options.all.subtracting(disabled) }

    private var parsed: ParsedEntry {
        QuickParser.parse(text, groups: groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName) }, options: options, now: Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            if focused, !text.isEmpty {
                previewChips
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: addedCount)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
                    #if os(iOS)
                    .submitLabel(.done)
                    #endif
                if !text.isEmpty {
                    Button(action: add) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.return, modifiers: .command)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: text.isEmpty)
        .animation(.snappy(duration: 0.25), value: focused)
        .onChange(of: app.wantsQuickEntryFocus) { _, wants in
            if wants { focusNow() }
        }
        .onAppear {
            if app.wantsQuickEntryFocus { focusNow() }
        }
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty { disabled = [] }
        }
    }

    private func focusNow() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
            app.wantsQuickEntryFocus = false
        }
    }

    private var previewChips: some View {
        let entry = parsed
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let groupName = entry.groupName {
                    chip(groupName, symbol: "folder", option: .group)
                } else {
                    let name = groups.first(where: { $0.uuid == defaultGroupID })?.displayName ?? "Quick Entry"
                    Label(name, systemImage: defaultGroupID == nil ? "tray.and.arrow.down" : "folder")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                if let due = entry.due {
                    chip(DateText.due(due, hasTime: entry.dueHasTime, today: app.dayStart), symbol: "calendar", option: .dates)
                }
                if entry.priority != .normal {
                    chip(entry.priority.title, symbol: entry.priority.symbol, option: .priority, color: entry.priority.color)
                }
                ForEach(entry.tags, id: \.self) { tag in
                    chip("#" + tag, symbol: nil, option: .tags, color: TheoColor.forTag(tag).color)
                }
                if !entry.hasExtras {
                    Text("Try: tomorrow 9am · !! · #tag · @group")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollClipDisabled()
    }

    /// Tapping a chip turns that kind of parsing off for this entry (keeps the raw text).
    private func chip(_ title: String, symbol: String?, option: QuickParser.Options, color: Color = .accentColor) -> some View {
        Button {
            disabled.insert(option)
        } label: {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
                Image(systemName: "xmark").imageScale(.small).opacity(0.6)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(color.opacity(0.12)), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            focused = false
            return
        }
        let entry = parsed
        let placement = NewTaskPlacement(rawValue: placementRaw) ?? .bottom
        withAnimation(.snappy) {
            _ = app.store.addTask(entry, defaultGroupID: defaultGroupID, placement: placement)
        }
        if let group = app.store.group(id: entry.groupID ?? defaultGroupID), group.isCollapsed {
            app.store.setCollapsed(group, false)
        }
        addedCount += 1
        text = ""
        disabled = []
        // Keep the keyboard up for rapid entry.
        focused = true
    }
}
