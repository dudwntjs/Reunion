import Foundation

struct PlaceResult: Decodable, Identifiable, Equatable {
    struct DisplayName: Decodable, Equatable { var text: String }
    struct Attribution: Decodable, Equatable {
        var provider: String?
        var providerUri: String?
    }
    var id: String
    var displayName: DisplayName
    var formattedAddress: String?
    var location: Coordinate
    var attributions: [Attribution]?
}
