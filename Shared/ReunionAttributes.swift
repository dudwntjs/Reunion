import ActivityKit
import Foundation

struct ReunionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var friendStatus: String
        var arrival: Date
        var progress: Double
    }
    var place: String
    var friendName: String
    var target: Date
    var isDemo: Bool
}
