import AppKit

/// Safety net for the main window: if launch ends without a visible window (seen with
/// apps that also have a menu bar extra), do what a click on the Dock icon does.
final class TheoMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            guard !hasWindow else { return }
            NSApp.activate()
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        }
    }
}
