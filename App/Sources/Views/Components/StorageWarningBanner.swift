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
                    banner(
                        symbol: "icloud.slash",
                        title: "Not syncing with your other devices",
                        message: "Theo couldn't open its iCloud store, so changes made here stay on this device. Quit and reopen Theo, and check that you're signed in to iCloud.",
                        detail: Persistence.startupError,
                        color: .orange,
                        canHide: true
                    )
                }
            }
        }
    }

    private func banner(symbol: String, title: String, message: String, detail: String?, color: Color, canHide: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .theoFont(.title3)
                .foregroundStyle(canHide ? color : Color.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .theoFont(.subheadline, weight: .semibold)
                Text(message)
                    .theoFont(.footnote)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .theoFont(.caption)
                        .opacity(0.8)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(canHide ? Color.primary : Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            if canHide {
                Button {
                    withAnimation(.snappy) { hidden = true }
                } label: {
                    Image(systemName: "xmark")
                        .theoFont(.caption, weight: .bold)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Hide until Theo restarts")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Red is strong enough for white text; orange stays a tint so the text reads in light and dark.
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
}
