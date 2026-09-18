import XCTest

@testable import ReunionCore

final class ReunionCoreTests: XCTestCase {
    func testDepartureSubtractsDurationAndBuffer() {
        let target = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertEqual(
            DeparturePlanner.departure(target: target, duration: 1080, bufferMinutes: 5),
            target.addingTimeInterval(-1380)
        )
    }

    func testFractionalGoogleDurationPreservesSeconds() throws {
        XCTAssertEqual(try XCTUnwrap(DeparturePlanner.parseDuration("123.456s")), 123.456, accuracy: 0.0001)
    }

    func testInvalidDurationsAreRejected() {
        for value in ["", "12", "-1s", "nans", "infs", "1h", "null"] {
            XCTAssertNil(DeparturePlanner.parseDuration(value), value)
        }
    }

    func testZeroDurationAllowed() {
        XCTAssertEqual(DeparturePlanner.parseDuration("0s"), 0)
    }

    func testDepartureCrossesMidnight() throws {
        let target = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T00:10:00Z"))
        XCTAssertEqual(
            DeparturePlanner.departure(target: target, duration: 1200, bufferMinutes: 5),
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-16T23:45:00Z"))
        )
    }

    func testNegativeInputsCannotMoveDepartureAfterTarget() {
        let target = Date()
        XCTAssertEqual(DeparturePlanner.departure(target: target, duration: -10, bufferMinutes: -5), target)
    }

    func testCoordinateValidation() {
        XCTAssertTrue(Coordinate(latitude: 37.5, longitude: 127).isValid)
        XCTAssertFalse(Coordinate(latitude: 91, longitude: 0).isValid)
        XCTAssertFalse(Coordinate(latitude: 0, longitude: .nan).isValid)
        XCTAssertFalse(Coordinate(latitude: 0, longitude: 181).isValid)
    }

    func testDisplayRoundsUpButDepartureUsesExactDuration() {
        let estimate = RouteEstimate(seconds: 61, distanceMeters: 100, source: "test", fetchedAt: .now)
        XCTAssertEqual(estimate.minutes, 2)
        let target = Date()
        XCTAssertEqual(
            DeparturePlanner.departure(target: target, duration: estimate.seconds, bufferMinutes: 0),
            target.addingTimeInterval(-61)
        )
    }
}
