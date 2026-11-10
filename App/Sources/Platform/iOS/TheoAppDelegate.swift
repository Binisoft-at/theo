#if os(iOS)
import UIKit

/// Handles the Home Screen quick action ("Quick Entry"), and registers for the silent pushes
/// CloudKit sends when something changed on another device, so changes arrive right away.
final class TheoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem, item.type.hasSuffix("quickentry") {
            QuickActions.pendingQuickEntry = true
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TheoSceneDelegate.self
        return configuration
    }
}

final class TheoSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if shortcutItem.type.hasSuffix("quickentry") {
            if let app = AppModel.shared {
                app.requestQuickEntry()
            } else {
                QuickActions.pendingQuickEntry = true
            }
        }
        completionHandler(true)
    }
}
#endif
