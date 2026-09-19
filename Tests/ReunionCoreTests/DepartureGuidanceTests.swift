import XCTest
@testable import ReunionCore

final class DepartureGuidanceTests: XCTestCase {
    func testDepartureWindowAndManualStates() {
        let departure = Date(timeIntervalSince1970: 10000)
        for (remaining, expected) in [
            (301.0, "아직 출발 안 해도 돼요"), (300, "이제 슬슬 출발하세요"), (1, "이제 슬슬 출발하세요"), (0, "지금 출발하세요"), (-1, "지금 출발하세요"),
        ] {
            XCTAssertEqual(
                DepartureGuidance.message(
                    phase: .free,
                    departure: departure,
                    now: departure.addingTimeInterval(-remaining)
                ),
                expected
            )
        }
        XCTAssertEqual(DepartureGuidance.message(phase: .moving, departure: departure), "약속 장소로 이동 중이에요")
        XCTAssertEqual(DepartureGuidance.message(phase: .arrived, departure: departure), "약속 장소에 도착했어요")
    }
}
