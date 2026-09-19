import Foundation

enum MapConfiguration {
    static func configured(_ name: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: name) as? String else {
            return ""
        }

        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || key.contains("$(") || key.hasPrefix("YOUR_") ? "" : key
    }
    static var nativeKey: String { configured("KAKAO_NATIVE_APP_KEY") }
    static var restKey: String { configured("KAKAO_REST_API_KEY") }
}
