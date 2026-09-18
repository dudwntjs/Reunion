import XCTest

@testable import ReunionCore

final class PlacesClientTests: XCTestCase {
    func testSearchUsesActualCoordinateAndQuery() throws {
        let coordinate = Coordinate(latitude: 37.5432, longitude: 127.0123)
        let request = try PlacesClient.makeRequest(query: "  카페  ", near: coordinate, key: "unit-test-key")
        let requestBody = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(body["textQuery"] as? String, "카페")
        let bias = try XCTUnwrap(body["locationBias"] as? [String: Any])
        let circle = try XCTUnwrap(bias["circle"] as? [String: Any])
        let center = try XCTUnwrap(circle["center"] as? [String: Double])
        XCTAssertEqual(center["latitude"], coordinate.latitude)
        XCTAssertEqual(center["longitude"], coordinate.longitude)
        XCTAssertEqual(circle["radius"] as? Double, 5000)
        XCTAssertEqual(request.url?.host, "places.googleapis.com")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testSearchRejectsMissingKeyQueryAndInvalidLocation() {
        let center = Coordinate(latitude: 37.5, longitude: 127)
        XCTAssertThrowsError(try PlacesClient.makeRequest(query: "카페", near: center, key: ""))
        XCTAssertThrowsError(try PlacesClient.makeRequest(query: "  ", near: center, key: "test"))
        XCTAssertThrowsError(
            try PlacesClient.makeRequest(query: "카페", near: .init(latitude: 91, longitude: 127), key: "test")
        )
    }

    func testGoogleResultCarriesSelectedCoordinates() throws {
        let response = """
            {
                "places": [
                    {
                        "id": "sample-place",
                        "displayName": { "text": "동네 카페" },
                        "formattedAddress": "테스트 주소",
                        "location": { "latitude": 37.55, "longitude": 126.98 }
                    }
                ]
            }
            """
        let data = Data(response.utf8)
        let result = try JSONDecoder().decode(PlacesClient.Response.self, from: data)
        XCTAssertEqual(result.places?.first?.displayName.text, "동네 카페")
        XCTAssertEqual(result.places?.first?.location, .init(latitude: 37.55, longitude: 126.98))
    }

    func testSearchWithoutLocationDoesNotRequireGPS() throws {
        let request = try PlacesClient.makeRequest(query: "서울시청", near: nil, key: "unit-test-key")
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["textQuery"] as? String, "서울시청")
        XCTAssertNil(body["locationBias"])
    }

    func testEmptyResponseDoesNotInventPlaces() throws {
        let result = try JSONDecoder().decode(PlacesClient.Response.self, from: Data("{}".utf8))
        XCTAssertTrue((result.places ?? []).isEmpty)
    }
}
