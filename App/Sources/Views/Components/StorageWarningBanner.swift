import SwiftUI

/// A banner above every page when Theo can't keep tasks the normal way, so nothing is lost
/// silently: red when they live in memory only (gone after quitting), orange when they stay on
/// this device because the iCloud store couldn't be opened. Shows nothing when all is well, and
/// never for the screenshot demo data.
struct StorageWarningBanner: View {
    /// The orange one can be put away for this launch; the red one stays.
    @State private var hidden = false

    private enum Warning {
        case notKept, notSyncing
    }

    private var warning: Warning? {
        guard !Persistence.isDemo else { return nil }
        switch Persistence.storeKind {
        case .cloud: return nil
        case .local: return AppIdentifiers.appCloudKitContainer != nil ? .notSyncing : nil
        case .memory: return .notKept
        }
    }

    #if os(iOS)
    /// The ✕ gets a full touch target without making the banner taller.
    private static let hideTarget: CGFloat = 44
    #else
    private static let hideTarget: CGFloat = 28
    #endif

    var body: some View {
        if let warning {
            switch warning {
            case .notKept:
                banner(
                    symbol: "exclamationmark.octagon.fill",
                    title: "Theo couldn't open your tasks",
                    message: "Nothing you add now will be kept. Quit and reopen Theo. Your iCloud data and your backups (Settings → Backups) are untouched.",
                    detail: Persistence.localError,
                    color: .red,
                    canHide: false
                )
            case .notSyncing:
                if !hidden {
                    // Put away, it slides up out of sight and the page moves up with it.
                    banner(
                        symbol: "icloud.slash",
                        title: "Not syncing with your other devices",
                        message: "Theo couldn't open its iCloud store, so changes made here stay on this device. Quit and reopen Theo, and check that you're signed in to iCloud.",
                        detail: Persistence.startupError,
                        color: .orange,
                        canHide: true
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func banner(symbol: String, title: String, message: String, detail: String?, color: Color, canHide: Bool) -> some View {
        // Red is strong enough for white text; orange stays a tint so the text reads in light and dark.
        let ink: Color = canHide ? Color.primary : Color.white
        let detailInk: AnyShapeStyle = canHide ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Color.white.opacity(0.75))
        let rendering: SymbolRenderingMode = canHide ? .hierarchical : .monochrome
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .theoFont(.title3)
                .symbolRenderingMode(rendering)
                .foregroundStyle(canHide ? color : Color.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .theoFont(.subheadline, weight: .semibold)
                Text(message)
                    .theoFont(.footnote)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .theoFont(.caption)
                        .foregroundStyle(detailInk)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if canHide {
                hideButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if canHide {
                ZStack {
                    Rectangle().fill(.bar)
                    Rectangle().fill(color.opacity(0.18))
                }
            } else {
                Rectangle().fill(color.gradient)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Puts the orange banner away until Theo restarts.
    private var hideButton: some View {
        Button {
            Motion.animate(Motion.layout) { hidden = true }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .theoFont(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Self.hideTarget, height: Self.hideTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        // As small as the glyph in the layout, so the banner keeps its height and margins.
        .padding((28 - Self.hideTarget) / 2)
        .accessibilityLabel("Hide until Theo restarts")
        .help("Hide until Theo restarts")
    }
}
