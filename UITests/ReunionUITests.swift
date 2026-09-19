import XCTest

final class ReunionUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    func reveal(_ element: XCUIElement) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
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
    func testThreeStatusButtonsWorkWithoutRouteOrLocationSharing() {
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertFalse(app.otherElements["togetherMap"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "여유시간")).firstMatch.exists)
        XCTAssertFalse(app.pickers.firstMatch.exists)
        XCTAssertFalse(app.buttons["phase-free"].exists)
        for phase in ["moving", "arrived"] {
            let button = app.buttons["phase-\(phase)"]
            button.tap()
            XCTAssertEqual(button.value as? String, "선택됨")
        }
        capture("kakao-reunion-status")
    }
    func testPlaceSelectionAndAppointmentUseOnlyTogetherMap() {
        app.terminate()
        app.launchEnvironment["REUNION_TEST_PLACES"] =
            #"[{"id":"cityhall","displayName":{"text":"서울시청"},"formattedAddress":"서울 중구 세종대로 110","location":{"latitude":37.5665,"longitude":126.978}}]"#
        app.launch()
        app.buttons["findPlace"].tap()
        let query = app.textFields["placeQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("서울시청")
        app.buttons["searchPlaces"].tap()
        let result = app.buttons["placeResult-cityhall"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let map = app.otherElements["togetherMap"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(map.frame.width, 100)
        XCTAssertGreaterThan(map.frame.height, 100)
        capture("kakao-live-map-first-open")
        app.tabBars.buttons["재합류"].tap()
        app.tabBars.buttons["함께 보기"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        capture("kakao-live-map-reopened")
        let choose = app.buttons["choosePlace"]
        reveal(choose)
        choose.tap()
        XCTAssertTrue(app.navigationBars["약속 정하기"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["togetherMap"].isHittable)
        XCTAssertTrue(app.buttons["saveMeeting"].isEnabled)
        app.buttons["saveMeeting"].tap()
        app.tabBars.buttons["재합류"].tap()
        XCTAssertTrue(app.staticTexts["서울시청"].exists)
        XCTAssertFalse(app.otherElements["togetherMap"].exists)
        capture("kakao-selected-meeting")
    }
    func testMultipleFriendsHaveSeparateStates() throws {
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
        XCTAssertTrue(app.staticTexts["4명 중 1명이 도착했어요"].exists)
        for name in ["민지", "지우", "수현"] {
            reveal(app.staticTexts[name])
            XCTAssertTrue(app.staticTexts[name].exists)
        }
        capture("kakao-friends")
    }
    func testInvitationUsesICloudWithoutKeyFields() {
        app.tabBars.buttons["함께 보기"].tap()
        reveal(app.buttons["connect"])
        app.buttons["connect"].tap()
        XCTAssertTrue(app.navigationBars["친구와 연결"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["내 이름"].exists)
        XCTAssertFalse(app.textFields["서버 HTTPS 주소"].exists)
        XCTAssertEqual(app.secureTextFields.count, 0)
        app.buttons["초대로 참여"].tap()
        let link = app.textFields["iCloud 초대 링크"]
        XCTAssertTrue(link.exists)
        link.tap()
        link.typeText("123456")
        XCTAssertFalse(app.buttons["참여하기"].isEnabled)
        capture("kakao-cloud-invite")
    }
}
