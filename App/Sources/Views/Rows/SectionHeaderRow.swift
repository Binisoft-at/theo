import SwiftUI
import TheoCore

/// A heading line on a page: Quick Entry, a group, or a computed section.
struct SectionHeaderRow: View {
    let info: SectionHeaderInfo
    let today: Date
    var onToggleCollapse: () -> Void
    var onAdd: (() -> Void)?

    private var title: String {
        switch info.kind {
        case .quickEntry: "Quick Entry"
        case .group(let group): group.displayName
        case .label(_, let title, _, _): title
        }
    }

    private var symbol: String {
        switch info.kind {
        case .quickEntry: "tray.and.arrow.down.fill"
        case .group(let group): group.symbol
        case .label(_, _, let symbol, _): symbol
        }
    }

    private var color: Color {
        switch info.kind {
        case .quickEntry: .secondary
        case .group(let group): group.color.color
        case .label(_, _, _, let color): color
        }
    }

    private var project: TaskGroup? {
        if case .group(let group) = info.kind, group.isProject { return group }
        return nil
    }

    private var total: Int { info.openCount + info.doneCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(minWidth: 22)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let project, let due = project.dueDate {
                    Text(DateText.due(due, hasTime: false, today: today))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.15)))
                        .foregroundStyle(color)
                }
                Spacer(minLength: 8)
                if total > 0 {
                    Text(info.doneCount > 0 ? "\(info.doneCount)/\(total)" : "\(info.openCount)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add task to \(title)")
                }
                if info.collapsible {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(info.isCollapsed ? 0 : 90))
                        .animation(.snappy, value: info.isCollapsed)
                }
            }
            if project != nil, total > 0 {
                ProgressView(value: Double(info.doneCount), total: Double(total))
                    .tint(color)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if info.collapsible { onToggleCollapse() }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
