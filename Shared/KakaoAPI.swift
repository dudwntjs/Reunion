import Foundation

enum KakaoAPI {
    enum Failure: LocalizedError {
        case missingKey, invalidInput, response, noRoute, http(Int)
        var errorDescription: String? {
            switch self {
            case .missingKey: "카카오 연결을 준비 중이에요. 연결 후 검색과 도보 경로를 사용할 수 있어요."
            case .invalidInput: "검색어나 위치를 확인해 주세요."
            case .response: "카카오 응답을 읽지 못했어요. 다시 시도해 주세요."
            case .noRoute: "이 구간의 도보 경로를 찾지 못했어요."
            case .http(let code): "카카오 연결에 실패했어요 (\(code)). 앱 키와 API 사용 설정을 확인해 주세요."
            }
        }
    }
    static func searchRequest(query: String, near: Coordinate?, key: String) throws -> URLRequest {
        var params = ["query": try nonempty(query), "size": "15"]
        if let near, near.isValid {
            params["x"] = "\(near.longitude)"
            params["y"] = "\(near.latitude)"
        }
        return try request("/v2/local/search/keyword.json", params: params, key: key)
    }
    static func addressRequest(query: String, key: String) throws -> URLRequest {
        try request("/v2/local/search/address.json", params: ["query": try nonempty(query)], key: key)
    }
    static func reverseRequest(coordinate: Coordinate, key: String) throws -> URLRequest {
        guard coordinate.isValid else { throw Failure.invalidInput }
        return try request(
            "/v2/local/geo/coord2address.json",
            params: [
                "x": "\(coordinate.longitude)", "y": "\(coordinate.latitude)", "input_coord": "WGS84",
            ],
            key: key
        )
    }
    static func routeRequest(from: Coordinate, to: Coordinate, key: String) throws -> URLRequest {
        guard from.isValid, to.isValid else { throw Failure.invalidInput }
        return try request(
            "/v2/routing/walk",
            params: [
                "start_x": "\(from.longitude)", "start_y": "\(from.latitude)",
                "end_x": "\(to.longitude)", "end_y": "\(to.latitude)",
            ],
            key: key
        )
    }
    static func search(query: String, near: Coordinate?, key: String) async throws -> [PlaceResult] {
        let request = try searchRequest(query: query, near: near, key: key)
        let places = try decodePlaces(await data(for: request))
        if !places.isEmpty { return places }
        let address = try addressRequest(query: query, key: key)
        return try decodeAddresses(await data(for: address))
    }
    static func decodePlaces(_ data: Data) throws -> [PlaceResult] {
        try documents(data)
            .compactMap { row in
                guard let point = point(row), let id = row["id"] as? String,
                    let name = row["place_name"] as? String
                else { return nil }
                let road = row["road_address_name"] as? String ?? ""
                return PlaceResult(
                    id: id,
                    displayName: .init(text: name),
                    formattedAddress: road.isEmpty ? row["address_name"] as? String : road,
                    location: point
                )
            }
    }
    static func decodeAddresses(_ data: Data) throws -> [PlaceResult] {
        try documents(data)
            .compactMap { row in
                guard let point = point(row), let name = row["address_name"] as? String else { return nil }
                return PlaceResult(
                    id: "address-\(point.latitude)-\(point.longitude)",
                    displayName: .init(text: name),
                    formattedAddress: name,
                    location: point
                )
            }
    }
    static func decodeAddress(_ data: Data) throws -> String? {
        guard let row = try documents(data).first else { return nil }
        let road = row["road_address"] as? [String: Any]
        let address = row["address"] as? [String: Any]
        return road?["address_name"] as? String ?? address?["address_name"] as? String
    }
    static func decodeRoute(_ data: Data) throws -> RouteEstimate {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (json["status"] as? String) == "OK", let route = json["route"] as? [String: Any],
            let properties = route["properties"] as? [String: Any],
            let seconds = properties["totalTime"] as? Double, let distance = properties["totalDistance"] as? Int,
            seconds.isFinite, seconds >= 0, distance >= 0
        else { throw Failure.noRoute }
        let steps = (route["legs"] as? [[String: Any]] ?? []).flatMap { $0["steps"] as? [[String: Any]] ?? [] }
        let coordinates = steps.flatMap { step -> [Coordinate] in
            let path = step["path"] as? [String: Any]
            return (path?["points"] as? [[Double]] ?? [])
                .compactMap { xy in
                    guard xy.count == 2 else { return nil }
                    let point = Coordinate(latitude: xy[1], longitude: xy[0])
                    return point.isValid ? point : nil
                }
        }
        let instructions = steps.compactMap { ($0["properties"] as? [String: Any])?["guidance"] as? String }
        return RouteEstimate(
            seconds: seconds,
            distanceMeters: distance,
            source: "카카오 도보 경로",
            fetchedAt: .now,
            instructions: instructions,
            coordinates: coordinates
        )
    }
    static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.response }
        guard (200...299).contains(response.statusCode) else { throw Failure.http(response.statusCode) }
        return data
    }
    private static func request(_ path: String, params: [String: String], key: String) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.missingKey }
        var url = URLComponents(string: "https://dapi.kakao.com" + path)!
        url.queryItems = params.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        guard let endpoint = url.url else { throw Failure.invalidInput }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("KakaoAK \(key)", forHTTPHeaderField: "Authorization")
        return request
    }
    private static func nonempty(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.invalidInput }
        return text
    }
    private static func documents(_ data: Data) throws -> [[String: Any]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = json["documents"] as? [[String: Any]]
        else { throw Failure.response }
        return rows
    }
    private static func point(_ row: [String: Any]) -> Coordinate? {
        guard let x = Double(row["x"] as? String ?? ""), let y = Double(row["y"] as? String ?? "") else { return nil }
        let point = Coordinate(latitude: y, longitude: x)
        return point.isValid ? point : nil
    }
}
