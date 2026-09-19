import XCTest

@testable import ReunionCore

final class KakaoAPITests: XCTestCase {
    func query(_ request: URLRequest) throws -> [String: String] {
        let url = try XCTUnwrap(request.url)
        return Dictionary(
            uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
                .map { ($0.name, $0.value ?? "") }
        )
    }
    func testKeywordSearchUsesRealLocationAndRESTAuthorization() throws {
        let request = try KakaoAPI.searchRequest(
            query: " 서울 카페 ",
            near: .init(latitude: 37.5, longitude: 127.1),
            key: "test-key"
        )
        XCTAssertEqual(request.url?.host, "dapi.kakao.com")
        XCTAssertEqual(request.url?.path, "/v2/local/search/keyword.json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "KakaoAK test-key")
        let params = try query(request)
        XCTAssertEqual(params["query"], "서울 카페")
        XCTAssertEqual(params["x"], "127.1")
        XCTAssertEqual(params["y"], "37.5")
    }
    func testSearchWorksWithoutGPSAndRejectsMissingConfiguration() throws {
        let request = try KakaoAPI.searchRequest(query: "서울역", near: nil, key: "test")
        XCTAssertNil(try query(request)["x"])
        XCTAssertThrowsError(try KakaoAPI.searchRequest(query: " ", near: nil, key: "test"))
        XCTAssertThrowsError(try KakaoAPI.searchRequest(query: "서울역", near: nil, key: ""))
        XCTAssertTrue(try KakaoAPI.decodePlaces(Data(#"{"documents":[]}"#.utf8)).isEmpty)
    }
    func testPlaceAndAddressCoordinatesUseLongitudeThenLatitude() throws {
        let places = try KakaoAPI.decodePlaces(
            Data(
                #"{"documents":[{"id":"1","place_name":"약속 카페","road_address_name":"도로명 주소","x":"127.1","y":"37.5"}]}"#
                    .utf8
            )
        )
        XCTAssertEqual(places.first?.location, .init(latitude: 37.5, longitude: 127.1))
        XCTAssertEqual(places.first?.formattedAddress, "도로명 주소")
        let addresses = try KakaoAPI.decodeAddresses(
            Data(#"{"documents":[{"address_name":"도로명 주소","x":"127.1","y":"37.5"}]}"#.utf8)
        )
        XCTAssertEqual(addresses.first?.location, places.first?.location)
        let reverse = try KakaoAPI.reverseRequest(coordinate: .init(latitude: 37.5, longitude: 127.1), key: "test")
        XCTAssertEqual(try query(reverse)["x"], "127.1")
        XCTAssertEqual(
            try KakaoAPI.decodeAddress(
                Data(#"{"documents":[{"address":{"address_name":"지번"},"road_address":{"address_name":"도로명"}}]}"#.utf8)
            ),
            "도로명"
        )
        XCTAssertEqual(
            try KakaoAPI.addressRequest(query: "도로명", key: "test").url?.path,
            "/v2/local/search/address.json"
        )
    }
    func testWalkingDurationRouteLineAndInstructions() throws {
        let request = try KakaoAPI.routeRequest(
            from: .init(latitude: 37.5, longitude: 127),
            to: .init(latitude: 37.6, longitude: 127.1),
            key: "test"
        )
        XCTAssertEqual(request.url?.path, "/v2/routing/walk")
        XCTAssertEqual(try query(request)["start_x"], "127.0")
        let route = try KakaoAPI.decodeRoute(
            Data(
                #"{"status":"OK","route":{"properties":{"totalTime":1242,"totalDistance":1400},"legs":[{"steps":[{"properties":{"guidance":"직진하세요"},"path":{"points":[[127,37.5],[127.1,37.6]]}}]}]}}"#
                    .utf8
            )
        )
        XCTAssertEqual(route.seconds, 1242)
        XCTAssertEqual(route.minutes, 21)
        XCTAssertEqual(
            route.coordinates,
            [.init(latitude: 37.5, longitude: 127), .init(latitude: 37.6, longitude: 127.1)]
        )
        XCTAssertEqual(route.instructions, ["직진하세요"])
        let target = Date()
        XCTAssertEqual(
            DeparturePlanner.departure(target: target, duration: route.seconds, bufferMinutes: 0),
            target.addingTimeInterval(-1242)
        )
        XCTAssertEqual(Meeting().bufferMinutes, 0)
    }
    func testUnavailableRoutesAndInvalidCoordinatesDoNotInventPaths() {
        XCTAssertThrowsError(try KakaoAPI.decodeRoute(Data(#"{"status":"NO_ROUTE"}"#.utf8)))
        XCTAssertThrowsError(try KakaoAPI.reverseRequest(coordinate: .init(latitude: 99, longitude: 127), key: "test"))
        XCTAssertThrowsError(
            try KakaoAPI.decodeRoute(
                Data(#"{"status":"OK","route":{"properties":{"totalTime":-2,"totalDistance":1}}}"#.utf8)
            )
        )
    }
}
