import Foundation

struct Peer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var phase: String
    var sharingEnabled: Bool?
    var coordinate: Coordinate?
    var updatedAt: Double
    var coordinateUpdatedAt: Double?
    var eta: Double?
}
extension Peer {
    var sharesLocation: Bool { sharingEnabled ?? (coordinate != nil) }
    var visibleCoordinate: Coordinate? { sharesLocation ? coordinate : nil }
    var isStale: Bool {
        guard let coordinateUpdatedAt else { return true }
        return Date().timeIntervalSince1970 - coordinateUpdatedAt > 30
    }
    var status: String {
        switch phase {
        case "moving": "만나러 오는 중"
        case "arrived": "도착했어요"
        case "complete": "재합류 완료"
        default: "자유시간 중"
        }
    }
    var sharingDescription: String {
        guard sharesLocation else {
            return Date().timeIntervalSince1970 - updatedAt > 30 ? "연결 확인 중 · 마지막 상태" : "위치 공유 꺼짐"
        }
        guard coordinate != nil, let coordinateUpdatedAt else { return "위치 확인 중" }
        if isStale {
            return "마지막 위치 · "
                + Date(timeIntervalSince1970: coordinateUpdatedAt)
                .formatted(date: .omitted, time: .shortened)
        }
        return "실시간 위치 공유 중"
    }
}

enum GroupStatus {
    static func summary(mine: JourneyPhase, peers: [Peer]) -> String {
        if mine == .complete { return "다시 만났어요" }
        guard !peers.isEmpty else { return "친구 연결을 기다리고 있어요" }
        let phases = [mine.rawValue] + peers.map(\.phase)
        let arrived = phases.filter { $0 == "arrived" }.count
        let moving = phases.filter { $0 == "moving" }.count
        if arrived == phases.count { return "모두 약속 장소에 도착했어요" }
        if arrived > 0 { return "\(phases.count)명 중 \(arrived)명이 도착했어요" }
        if moving > 0 { return "\(phases.count)명 중 \(moving)명이 만나러 가고 있어요" }
        return "각자 자유시간을 보내고 있어요"
    }
    static func friendsSummary(_ peers: [Peer]) -> String {
        guard !peers.isEmpty else { return "친구 참여 대기" }
        let arrived = peers.filter { $0.phase == "arrived" }.count
        let moving = peers.filter { $0.phase == "moving" }.count
        return "친구 \(peers.count)명 · 이동 \(moving)명 · 도착 \(arrived)명"
    }
}
