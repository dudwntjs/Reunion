import Foundation

struct Coordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    static let unset = Coordinate(latitude: 0, longitude: 0)
}

enum TravelMode: String, Codable, CaseIterable, Identifiable {
    case walk = "WALK", drive = "DRIVE", transit = "TRANSIT"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walk: "도보"
        case .drive: "자동차"
        case .transit: "대중교통"
        }
    }
    var icon: String {
        switch self {
        case .walk: "figure.walk"
        case .drive: "car.fill"
        case .transit: "tram.fill"
        }
    }
    var mapsValue: String {
        switch self {
        case .walk: "walking"
        case .drive: "driving"
        case .transit: "transit"
        }
    }
}

struct Meeting: Codable, Equatable {
    var place = ""
    var note = ""
    var coordinate = Coordinate.unset
    var origin = Coordinate.unset
    var target = Date().addingTimeInterval(45 * 60)
    var bufferMinutes = 0
    var mode = TravelMode.walk
    var friendName = "친구"
}

struct RouteEstimate: Codable, Equatable {
    var seconds: TimeInterval
    var distanceMeters: Int
    var source: String
    var fetchedAt: Date
    var encodedPolyline: String?
    var instructions: [String]? = nil
    var coordinates: [Coordinate]? = nil
    static var demo: Self { .init(seconds: 18 * 60, distanceMeters: 1300, source: "시뮬레이션", fetchedAt: .now) }
    var minutes: Int { Int(ceil(seconds / 60)) }
}

enum DeparturePlanner {
    static func departure(

        target: Date,
        duration: TimeInterval,
        bufferMinutes: Int
    ) -> Date {
        target.addingTimeInterval(-max(0, duration) - Double(max(0, bufferMinutes)) * 60)
    }

    static func parseDuration(_ value: String) -> TimeInterval? {
        guard value.hasSuffix("s"), let seconds = Double(value.dropLast()), seconds.isFinite, seconds >= 0 else {
            return nil
        }

        return seconds
    }
}

enum JourneyPhase: String, Codable { case free, moving, arrived, complete }
enum PromptKind: String, Identifiable {
    case soon, now, movement
    var id: String { rawValue }
    var title: String {
        switch self {
        case .soon: "곧 출발할 시간이에요!"
        case .now: "지금 출발하면\n여유롭게 만날 수 있어요"
        case .movement: "출발하셨나요?"
        }
    }
    var body: String {
        switch self {
        case .soon: "슬슬 마무리해 볼까요? 출발 5분 전에 알려드려요."
        case .now: "도보 이동시간을 고려한 출발 안내예요."
        case .movement: "위치가 달라졌어요. 약속 장소로 출발했다면 확인해 주세요."
        }
    }
}

struct StudyEvent: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var type: String
    var detail: String
}
struct StudyReport: Codable, Identifiable {
    var id = UUID()
    var sessionID: UUID
    var date = Date()
    var condition: String
    var contactCount: Int
    var convenience: Int
    var usefulness: Int
    var comment: String
    var routeSource: String
    var events: [StudyEvent]
}

enum DepartureGuidance {
    static func message(phase: JourneyPhase, departure: Date?, now: Date = .now) -> String {
        switch phase {
        case .moving: return "약속 장소로 이동 중이에요"
        case .arrived: return "약속 장소에 도착했어요"
        case .complete: return "재합류를 마쳤어요"
        case .free:
            guard let departure else { return "출발 시간을 확인해 주세요" }
            let remaining = departure.timeIntervalSince(now)
            if remaining <= 0 { return "지금 출발하세요" }
            if remaining <= 300 { return "이제 슬슬 출발하세요" }
            return "아직 출발 안 해도 돼요"
        }
    }
}
