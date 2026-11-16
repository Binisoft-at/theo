#if os(macOS)
import AppKit
import CoreServices
import SwiftUI

enum MainWindow {
    static var isVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    /// Opens the main window when none is showing, by sending ourselves the "reopen" Apple
    /// event a click on the Dock icon sends (works from anywhere, no SwiftUI environment needed).
    @MainActor
    static func reopen() {
        NSApp.activate()
        guard !isVisible else { return }
        let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 2)
        } catch {
            print("Theo: reopen event failed: \(error)")
        }
    }
}

/// The menu bar icon. It is the one SwiftUI view that exists right after launch, so it
/// makes sure the main window is open (apps with a menu bar extra can start without it).
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "checkmark.circle")
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !MainWindow.isVisible else { return }
                print("Theo: opening main window from menu bar label")
                openWindow(id: "main")
            }
    }
}

/// The Mac's app-level hooks: the Quick Add shortcut, the daily care a window's scene phase
/// doesn't trigger on the Mac (it stays "active" for days), a save on quit, and the Dock menu.
/// Last-resort safety net: if there is still no window shortly after launch, it sends itself the
/// same "reopen" Apple event a click on the Dock icon sends.
final class TheoMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // CloudKit's silent pushes: changes from the iPhone arrive within seconds instead of
        // whenever the Mac happens to check.
        NSApplication.shared.registerForRemoteNotifications()
        MainActor.assumeIsolated {
            GlobalHotKey.shared.apply(HotKeyChoice.stored)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !MainWindow.isVisible else { return }
            print("Theo: opening main window via reopen event")
            MainWindow.reopen()
        }
        // Screenshots: the Quick Add panel over the window, with a sample task typed in.
        if ProcessInfo.processInfo.arguments.contains("-TheoQuickAddPanel") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                QuickAddPanel.shared.state.text = "Report bis Freitag !! #work"
                QuickAddPanel.shared.show()
            }
        }
    }

    /// Switching back to Theo: a new day, the daily backup and the reminders are checked here,
    /// because the window's scene phase doesn't change when another app comes to the front.
    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let app = AppModel.shared else { return }
            app.refreshDay()
            app.backups.backUpIfDue()
            app.reminders?.scheduleSoon()
        }
    }

    /// ⌘Q right after typing: hand the last edits to the store (and iCloud) instead of relying
    /// on autosave.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let app = AppModel.shared else { return }
            app.store.save()
        }
    }

    /// Right-click on the Dock icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newTask = NSMenuItem(title: "New Task", action: #selector(dockNewTask), keyEquivalent: "")
        newTask.target = self
        menu.addItem(newTask)
        let today = NSMenuItem(title: "Today", action: #selector(dockToday), keyEquivalent: "")
        today.target = self
        menu.addItem(today)
        return menu
    }

    /// The Dock is already about Theo, so this opens its window with the cursor in the bar at
    /// the bottom, whatever the Quick Add shortcut opens.
    @objc private func dockNewTask() {
        MainActor.assumeIsolated {
            GlobalHotKey.focusComposer()
        }
    }

    @objc private func dockToday() {
        MainActor.assumeIsolated {
            MainWindow.reopen()
            AppModel.shared?.go(.today)
        }
    }
}
#endif
