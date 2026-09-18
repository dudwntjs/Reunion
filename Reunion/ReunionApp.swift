import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var pushToken: String?
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = GoogleMapsSetup.enabled
        _ = NotificationService.shared
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token =
            deviceToken.map {
                String(format: "%02x", $0)
            }
            .joined()
        Self.pushToken = token
        NotificationCenter.default.post(name: .init("ReunionPushToken"), object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Real APNs requires a signed physical-device build with the Push Notifications capability.
    }
}
@main struct ReunionApp: App {

    // MARK: - Properties

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = ReunionStore()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
