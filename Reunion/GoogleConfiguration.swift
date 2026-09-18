import Foundation

enum GoogleConfiguration {
    static func configured(_ name: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: name) as? String else {
            return ""
        }

        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || key.contains("$(") || key.hasPrefix("YOUR_") ? "" : key
    }
    static var placesKey: String { configured("GOOGLE_PLACES_API_KEY") }
    static var routesKey: String { configured("GOOGLE_ROUTES_API_KEY") }
}
