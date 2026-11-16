import Foundation
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Connects the app with its widgets. Keeps their snapshot of today's page current through a
/// `WidgetSnapshotWriter` (rebuilt after every save, here or from another device through iCloud,
/// when the day-start setting changes and when a new day starts), plus when Theo comes to the
/// front and right before it goes to the background or quits. Started once by `TheoApp`.
@MainActor
enum WidgetBridge {
    private static var writer: WidgetSnapshotWriter?
    private static var observers: [NSObjectProtocol] = []

    static func start(app: AppModel) {
        // The Control Center button runs its action inside the app and hands its link here.
        WidgetLinks.handler = { [weak app] url in
            app?.openLink(url)
        }
        // The screenshot demo data and a store that couldn't be opened (nothing would be kept)
        // never replace what the widgets show.
        guard writer == nil, !app.isSandbox, !Persistence.isDemo, Persistence.storeKind != .memory else { return }
        writer = WidgetSnapshotWriter(container: app.container)
        let center = NotificationCenter.default
        #if os(iOS)
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetBridge.writer?.scheduleSoon(after: 0.5) }
        })
        // iOS may suspend Theo right after this: the last change shouldn't wait for the next launch.
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetBridge.writer?.writeNow() }
        })
        #elseif os(macOS)
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetBridge.writer?.scheduleSoon(after: 0.5) }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetBridge.writer?.writeNow() }
        })
        #endif
    }
}

extension AppModel {
    /// The links widgets and Control Center open (RootView's `onOpenURL`):
    /// `theo://today`, `theo://task/<id>` (that task, or Today when it's gone) and
    /// `theo://quick-entry` (the cursor in the new-task field).
    func openLink(_ url: URL) {
        guard url.scheme?.lowercased() == "theo" else { return }
        // Theo may have slept overnight: the links mean the current day.
        refreshDay()
        #if os(macOS)
        NSApp.activate()
        #endif
        let host = url.host()?.lowercased() ?? ""
        switch host {
        case "task":
            let idText = url.pathComponents.first { $0 != "/" } ?? ""
            if let id = UUID(uuidString: idText), let task = store.task(id: id), task.deletedAt == nil {
                reveal(task)
            } else {
                go(.today)
            }
        case "quick-entry":
            #if os(iOS)
            // Still on its way to the front: RootView asks again once the scene is active.
            if UIApplication.shared.applicationState != .active {
                QuickActions.pendingQuickEntry = true
            }
            #endif
            requestQuickEntry()
        default:
            go(.today)
        }
        #if os(macOS)
        // A minimised window: bring it back (MainWindow.reopen() does nothing while a window
        // shows). Delayed, so a window SwiftUI is just opening for this link is on screen first.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            MainWindow.reopen()
        }
        #endif
    }
}
