import ActivityKit
import CoreLocation
import Foundation
import Security
import UserNotifications

struct RoutesClient {
    func estimate(meeting: Meeting, key: String) async throws -> RouteEstimate {
        let request = try KakaoAPI.routeRequest(from: meeting.origin, to: meeting.coordinate, key: key)
        return try KakaoAPI.decodeRoute(await KakaoAPI.data(for: request))
    }
}

enum KeyStore {
    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ReunionPoC.Routes",
            kSecAttrAccount as String: "api-key", kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ReunionPoC.Routes",
            kSecAttrAccount as String: "api-key",
        ]
        SecItemDelete(query as CFDictionary)

        guard !key.isEmpty else { return true }

        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocation) -> Void)?
    var onError: ((String) -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: onError?("위치 권한이 꺼져 있어요. iPhone 설정에서 허용해 주세요.")
        }
    }

    func enableBackgroundSharing() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        start()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied {
            onError?("위치 권한을 허용하지 않았어요. iPhone 설정에서 위치 사용을 허용해 주세요.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
            abs(location.timestamp.timeIntervalSinceNow) < 30
        else {
            return
        }

        onLocation?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?("현재 위치를 가져오지 못했어요. 잠시 후 다시 시도해 주세요.")
    }
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func schedule(departure: Date, place: String) async throws -> Bool {
        let center = UNUserNotificationCenter.current()

        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
            return false
        }

        cancel()
        for (id, date, title) in [
            ("soon", departure.addingTimeInterval(-300), "곧 출발할 시간이에요!"),
            ("now", departure, "지금 출발해야 친구와 다시 만날 수 있어요!"),
        ] where date > Date() {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "\(place)에서 다시 만나요. 앱에서 출발 여부를 확인해 주세요."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow),
                repeats: false
            )
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        return true
    }

    func friendDeparture(peer: Peer) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "\(peer.name)님이 출발했어요"
        content.body = "앱에서 친구의 이동 상태를 확인해 주세요."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "friend-\(peer.id)", content: content, trigger: nil))
    }

    func demoFriendDeparture(name: String) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "[체험] \(name)님이 출발했어요"
        content.body = "앱에서 친구의 이동 상태 예시를 확인해 보세요."
        content.sound = .default
        try await center.add(
            UNNotificationRequest(
                identifier: "friend-demo",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
        )
    }

    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["soon", "now", "friend-demo"])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        await MainActor.run {
            NotificationCenter.default.post(name: .init("ReunionNotificationTapped"), object: id)
        }
    }
}
