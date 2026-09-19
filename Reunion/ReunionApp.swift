import CloudKit
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static weak var store: ReunionStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = KakaoMapsSetup.enabled
        _ = NotificationService.shared
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let metadata = options.cloudKitShareMetadata { Self.receive(metadata) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CloudSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Self.receive(cloudKitShareMetadata)
    }

    static func receive(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == SessionClient.containerID,
            let url = metadata.share.url
        else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: "reunion.pendingInvitation")
        NotificationCenter.default.post(name: .init("ReunionCloudInvitation"), object: nil)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let store = Self.store ?? ReunionStore()
            let updated = await store.refreshCloud()
            completionHandler(updated ? .newData : .noData)
        }
    }
}

final class CloudSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        AppDelegate.receive(cloudKitShareMetadata)
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
