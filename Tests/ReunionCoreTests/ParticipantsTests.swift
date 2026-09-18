import XCTest
@testable import ReunionCore

final class ParticipantsTests: XCTestCase {
    func peer(_ id: String, phase: String = "free", sharing: Bool = true) -> Peer {
        Peer(
            id: id,
            name: "같은 이름",
            phase: phase,
            sharingEnabled: sharing,
            coordinate: Coordinate(latitude: 37, longitude: 127),
            updatedAt: Date().timeIntervalSince1970,
            coordinateUpdatedAt: Date().timeIntervalSince1970,
            eta: nil
        )
    }
    func testGroupRequiresEveryParticipantToArrive() {
        let peers = [peer("a", phase: "arrived"), peer("b", phase: "moving")]
        XCTAssertEqual(GroupStatus.summary(mine: .arrived, peers: peers), "3명 중 2명이 도착했어요")
        XCTAssertEqual(GroupStatus.friendsSummary(peers), "친구 2명 · 이동 1명 · 도착 1명")
        XCTAssertEqual(
            GroupStatus.summary(mine: .arrived, peers: [peer("a", phase: "arrived"), peer("b", phase: "arrived")]),
            "모두 약속 장소에 도착했어요"
        )
    }
    func testSharingAndFreshnessAreIndependentPerFriend() {
        var old = peer("old")
        old.coordinateUpdatedAt = Date().timeIntervalSince1970 - 90
        let hidden = peer("hidden", sharing: false)
        let current = peer("current")
        XCTAssertTrue(old.isStale)
        XCTAssertNotNil(old.visibleCoordinate)
        XCTAssertNil(hidden.visibleCoordinate)
        XCTAssertFalse(current.isStale)
        XCTAssertEqual([old, hidden, current].compactMap(\.visibleCoordinate).count, 2)
        XCTAssertEqual(Set([old, hidden, current].map(\.id)).count, 3)
    }
}
