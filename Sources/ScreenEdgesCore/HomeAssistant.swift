import Foundation

public struct HALight: Equatable, Sendable, Identifiable {
    public var id: String { entityId }
    public var entityId: String
    public var name: String
    public var platform: String?

    public init(entityId: String, name: String, platform: String? = nil) {
        self.entityId = entityId
        self.name = name
        self.platform = platform
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

    public func listLights(localtuyaOnly: Bool) async throws -> [HALight] {
        let data = try await get(path: "/api/states")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw HAClientError.unexpected("states JSON")
        }
        var lights: [HALight] = []
        for row in rows {
            guard let entityId = row["entity_id"] as? String, entityId.hasPrefix("light.") else { continue }
            let attrs = row["attributes"] as? [String: Any] ?? [:]
            let name = (attrs["friendly_name"] as? String) ?? entityId
            if localtuyaOnly {
                // Battletron zone lights from localtuya use "_zone_" in the entity id.
                let ok = entityId.contains("_zone_")
                    || entityId.contains("battletron")
                    || name.localizedCaseInsensitiveContains("zone")
                if !ok { continue }
            }
            lights.append(HALight(entityId: entityId, name: name))
        }
        return lights.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func setLightRGB(entityId: String, rgb: RGB) async throws {
        guard !entityId.isEmpty else { return }
        try await post(
            path: "/api/services/light/turn_on",
            body: [
                "entity_id": entityId,
                "rgb_color": [rgb.r, rgb.g, rgb.b],
                "brightness": max(rgb.r, rgb.g, rgb.b, 1),
            ]
        )
    }

    public func turnOff(entityId: String) async throws {
        guard !entityId.isEmpty else { return }
        try await post(path: "/api/services/light/turn_off", body: ["entity_id": entityId])
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
