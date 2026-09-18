import XCTest

final class ReunionUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testMultipleFriendsHaveSeparateStatusRows() throws {
        app.terminate()
        let peers: [[String: Any]] = [
            [
                "id": "one", "name": "민지", "phase": "moving", "sharingEnabled": false,
                "updatedAt": Date().timeIntervalSince1970,
            ],
            [
                "id": "two", "name": "지우", "phase": "arrived", "sharingEnabled": false,
                "updatedAt": Date().timeIntervalSince1970,
            ],
            [
                "id": "three", "name": "수현", "phase": "free", "sharingEnabled": false,
                "updatedAt": Date().timeIntervalSince1970,
            ],
        ]
        app.launchEnvironment["REUNION_TEST_PEERS"] = String(
            data: try JSONSerialization.data(withJSONObject: peers),
            encoding: .utf8
        )
        app.launch()
        app.tabBars.buttons["함께 보기"].tap()
        reveal(app.staticTexts["4명 중 1명이 도착했어요"])
        XCTAssertTrue(app.staticTexts["4명 중 1명이 도착했어요"].waitForExistence(timeout: 5))
        for name in ["민지", "지우", "수현"] {
            reveal(app.staticTexts[name])
            XCTAssertTrue(app.staticTexts[name].exists)
        }
        capture("multiple-friends")
    }

    func reveal(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.exists { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.3)))
        }
    }

    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNativeTabsAndNoDeveloperConfiguration() {
        XCTAssertTrue(app.buttons["findPlace"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["재합류"].exists)
        XCTAssertTrue(app.tabBars.buttons["함께 보기"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertFalse(app.buttons["settings"].exists)
        XCTAssertFalse(app.buttons["connect"].exists)
        capture("01-native-reunion")
        app.tabBars.buttons["함께 보기"].tap()
        XCTAssertTrue(app.staticTexts["친구 연결을 기다리고 있어요"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "connect").count, 1)
        XCTAssertFalse(app.buttons["showMeetingRoute"].exists)
        reveal(app.switches["sharingToggle"])
        XCTAssertTrue(app.switches["sharingToggle"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.switches["sharingToggle"].isEnabled)
        capture("02-native-together")
    }

    func testNativeMeetingFormRequiresAPlace() {
        app.buttons["findPlace"].tap()
        XCTAssertTrue(app.navigationBars["약속 정하기"].waitForExistence(timeout: 5))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.alerts.buttons["앱을 사용하는 동안 허용"].waitForExistence(timeout: 2) {
            system.alerts.buttons["앱을 사용하는 동안 허용"].tap()
        } else if system.alerts.buttons["Allow While Using App"].exists {
            system.alerts.buttons["Allow While Using App"].tap()
        }
        XCTAssertFalse(app.buttons["saveMeeting"].isEnabled)
        XCTAssertTrue(app.staticTexts["약속 시간"].exists)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        capture("03-native-meeting")
    }

    func testInvitationHasNoServerOrAPIKeyFields() {
        app.tabBars.buttons["함께 보기"].tap()
        app.buttons["connect"].tap()
        XCTAssertTrue(app.navigationBars["친구와 연결"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["내 이름"].exists)
        XCTAssertFalse(app.textFields["서버 HTTPS 주소"].exists)
        XCTAssertEqual(app.secureTextFields.count, 0)
        capture("04-native-invite")
    }
}
