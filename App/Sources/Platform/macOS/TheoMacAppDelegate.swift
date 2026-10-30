#if os(macOS)
import AppKit
import CoreServices
import SwiftUI

enum MainWindow {
    static var isVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
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

/// Last-resort safety net: if there is still no window shortly after launch, send ourselves
/// the same "reopen" Apple event a click on the Dock icon sends.
final class TheoMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !MainWindow.isVisible else { return }
            print("Theo: opening main window via reopen event")
            NSApp.activate()
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
}
#endif
