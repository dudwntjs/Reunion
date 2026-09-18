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
struct RemoteSession: Codable {
    var code: String
    var meeting: Meeting
    var participants: [Peer]
    var ended: Bool
}
struct SessionCredentials: Codable {
    var server: String
    var code: String
    var participantID: String
    var token: String
}
struct SessionReply: Codable {
    var session: RemoteSession
    var participantID: String
    var token: String
}
struct SessionClient {
    enum Failure: LocalizedError {
        case invalidURL, server(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: "서버의 HTTPS 주소를 확인해 주세요."
            case .server(let message): message
            }
        }
    }

    static func request<T: Decodable>(

        _ path: String,
        server: String,
        token: String? = nil,
        body: Data? = nil
    )
        async throws -> T
    {
        guard let base = URL(string: server), let host = base.host, !host.isEmpty,
            base.scheme == "https"
                || (base.scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")))
        else {
            throw Failure.invalidURL
        }

        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message =
                (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "서버에 연결할 수 없어요. 주소와 네트워크를 확인해 주세요."
            throw Failure.server(message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
    private struct ServerError: Decodable { var error: String }
    static func connect(

        server: String,
        name: String,
        code: String?,
        meeting: Meeting
    ) async throws -> SessionReply {
        struct Payload: Encodable {
            var name: String
            var code: String?
            var meeting: Meeting
        }
        var publicMeeting = meeting
        publicMeeting.origin = meeting.coordinate  // Do not send a private pre-departure origin to the relay.
        return try await request(
            code == nil ? "sessions" : "sessions/join",
            server: server,
            body: JSONEncoder().encode(Payload(name: name, code: code, meeting: publicMeeting))
        )
    }

    static func state(_ credentials: SessionCredentials) async throws -> RemoteSession {
        try await request("sessions/\(credentials.code)", server: credentials.server, token: credentials.token)
    }

    static func update(

        _ credentials: SessionCredentials,
        phase: JourneyPhase,
        sharingEnabled: Bool,
        coordinate: Coordinate?,
        coordinateUpdatedAt: Date?,
        eta: Date?,
        deviceToken: String?,
        activityToken: String?
    ) async throws -> RemoteSession {
        struct Payload: Encodable {
            var phase: String
            var sharingEnabled: Bool
            var coordinate: Coordinate?
            var coordinateUpdatedAt: Double?
            var eta: Double?
            var deviceToken: String?
            var activityToken: String?
        }
        return try await request(
            "sessions/\(credentials.code)/update",
            server: credentials.server,
            token: credentials.token,
            body: JSONEncoder()
                .encode(
                    Payload(
                        phase: phase.rawValue,
                        sharingEnabled: sharingEnabled,
                        coordinate: coordinate,
                        coordinateUpdatedAt: coordinateUpdatedAt?.timeIntervalSince1970,
                        eta: eta?.timeIntervalSince1970,
                        deviceToken: deviceToken,
                        activityToken: activityToken
                    )
                )
        )
    }

    static func end(_ credentials: SessionCredentials) async throws -> RemoteSession {
        try await request(
            "sessions/\(credentials.code)/end",
            server: credentials.server,
            token: credentials.token,
            body: Data("{}".utf8)
        )
    }
}
