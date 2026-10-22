import Foundation

public struct HASyncZone: Codable, Sendable, Identifiable {
    public let entityId: String
    public let name: String
    public let deviceName: String
    public let cm: Int
    public let sections: Int
    public let outputEnabled: Bool?
    public var id: String { entityId }
    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id", deviceName = "device_name", name, cm, sections, outputEnabled = "output_enabled"
    }
}

public struct HASyncLayout: Codable, Sendable {
    public let protocolVersion: Int
    public let samplesPerEdge: Int
    public let zones: [HASyncZone]
    public let owners: [String]
    public func outputEnabled(for mappings: [ZoneMapping]) -> Bool {
        let selected = Set(mappings.map(\.entityId))
        return zones.filter { selected.contains($0.entityId) }.allSatisfy { $0.outputEnabled != false }
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", samplesPerEdge = "samples_per_edge", zones, owners
    }
}

public enum HAClientError: Error, LocalizedError, Sendable {
    case badURL
    case notConnected
    case authFailed(String)
    case unexpected(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Home Assistant URL"
        case .notConnected: return "Not connected to Home Assistant"
        case .authFailed(let m): return m
        case .unexpected(let m): return m
        case .http(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}

/// Home Assistant REST API (long-lived token). Avoids WebSocket frame size limits.
public actor HomeAssistantClient {
    private var baseURL: URL?
    private var token: String = ""
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    public var isConnected: Bool { baseURL != nil && !token.isEmpty }

    public func connect(urlString: String, token: String) async throws {
        disconnect()
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { throw HAClientError.badURL }
        if components.scheme == nil { components.scheme = "http" }
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        guard let root = components.url else { throw HAClientError.badURL }
        self.baseURL = root
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cheap auth check — small response, no giant entity dump.
        let data = try await get(path: "/api/")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["message"] as? String != nil || obj["version"] != nil
        else {
            throw HAClientError.unexpected("unexpected /api/ response")
        }
    }

    public func disconnect() {
        baseURL = nil
        token = ""
    }

    public func syncLayout() async throws -> HASyncLayout {
        let layout = try JSONDecoder().decode(HASyncLayout.self, from: await get(path: "/api/localtuya/screen_sync"))
        guard layout.protocolVersion == 1, layout.samplesPerEdge == 20 else {
            throw HAClientError.unexpected("Incompatible LocalTuya screen-sync version")
        }
        return layout
    }

    public func startStream(config: AppConfig, port: UInt16) async throws {
        try await post(path: "/api/localtuya/screen_sync", body: [
            "action": "start", "owner": config.ownerID, "port": Int(port), "token": config.streamToken,
            "mappings": config.mappings.map { ["entity_id": $0.entityId, "edge": $0.edge.rawValue, "reverse": $0.reverse] as [String: Any] },
        ])
    }

    public func stopStream(owner: String) async throws {
        try await post(path: "/api/localtuya/screen_sync", body: ["action": "stop", "owner": owner])
    }

    private func get(path: String) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post(path: String, body: [String: Any]) async throws {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await perform(request)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL, !token.isEmpty else { throw HAClientError.notConnected }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HAClientError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HAClientError.unexpected(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw HAClientError.unexpected("no HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HAClientError.authFailed(body.isEmpty ? "Token rejected (\(http.statusCode))" : body)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HAClientError.http(http.statusCode, String(body.prefix(200)))
        }
        return data
    }
}
