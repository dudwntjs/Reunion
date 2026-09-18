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

struct PlacesClient {
    var session: URLSession = .shared
    struct Response: Decodable { var places: [PlaceResult]? }
    enum Failure: LocalizedError {
        case missingKey, missingQuery, invalidLocation, http(Int), invalidResponse
        var errorDescription: String? {
            switch self {
            case .missingKey: "장소 검색 서비스를 준비 중이에요. 연결이 준비되면 검색할 수 있어요."
            case .missingQuery: "찾고 싶은 장소나 카테고리를 입력해 주세요."
            case .invalidLocation: "현재 위치를 확인한 뒤 다시 검색해 주세요."
            case .http(let code): "Google 장소 검색에 연결하지 못했어요 (\(code)). 키의 Places API (New) 활성화와 결제 설정을 확인해 주세요."
            case .invalidResponse: "검색 결과를 읽지 못했어요. 다시 검색해 주세요."
            }
        }
    }

    static func makeRequest(

        query: String,
        near: Coordinate?,
        key: String
    ) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingKey
        }

        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { throw Failure.missingQuery }

        if let near, !near.isValid { throw Failure.invalidLocation }

        guard let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchText") else {
            throw Failure.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location,places.attributions",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        var body: [String: Any] = [
            "textQuery": query, "languageCode": "ko", "pageSize": 12,
        ]
        if let near {
            body["locationBias"] = [
                "circle": ["center": ["latitude": near.latitude, "longitude": near.longitude], "radius": 5000.0]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func search(

        query: String,
        near: Coordinate?,
        key: String
    ) async throws -> [PlaceResult] {
        let request = try Self.makeRequest(query: query, near: near, key: key)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }

        guard (200...299).contains(http.statusCode) else { throw Failure.http(http.statusCode) }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.places ?? [])
            .filter {
                $0.location.isValid
            }
    }
}
