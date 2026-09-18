import Foundation

enum CloudInvitation {
    static func url(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https",
            ["www.icloud.com", "icloud.com"].contains(url.host?.lowercased() ?? ""),
            url.user == nil, url.password == nil, url.port == nil,
            url.path.hasPrefix("/share/"), url.path.count > "/share/".count
        else { return nil }
        return url
    }
}
