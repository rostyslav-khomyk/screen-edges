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

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Home Assistant URL"
        case .notConnected: return "Not connected to Home Assistant"
        case .authFailed(let m): return m
        case .unexpected(let m): return m
        }
    }
}

/// Home Assistant WebSocket API (access token → call_service / entity registry).
public actor HomeAssistantClient {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var authContinuation: CheckedContinuation<Data, Error>?
    private var receiveTask: Task<Void, Never>?

    public init() {}

    public var isConnected: Bool { task != nil }

    public func connect(urlString: String, token: String) async throws {
        disconnect()
        guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw HAClientError.badURL
        }
        if components.scheme == "http" { components.scheme = "ws" }
        if components.scheme == "https" { components.scheme = "wss" }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty || path == "/" {
            path = "/api/websocket"
        } else if !path.hasSuffix("/api/websocket") {
            path += "/api/websocket"
        }
        components.path = path
        guard let url = components.url else { throw HAClientError.badURL }

        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveTask = Task { await self.readLoop() }

        let hello = try decode(try await waitAuthMessage())
        guard hello["type"] as? String == "auth_required" else {
            throw HAClientError.unexpected("expected auth_required")
        }
        try await sendRaw(["type": "auth", "access_token": token])
        let auth = try decode(try await waitAuthMessage())
        guard auth["type"] as? String == "auth_ok" else {
            throw HAClientError.authFailed((auth["message"] as? String) ?? "login rejected")
        }
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        let waiting = pending
        pending.removeAll()
        for (_, cont) in waiting { cont.resume(throwing: HAClientError.notConnected) }
        authContinuation?.resume(throwing: HAClientError.notConnected)
        authContinuation = nil
    }

    public func listLights(localtuyaOnly: Bool) async throws -> [HALight] {
        let result = try await sendCommand(["type": "config/entity_registry/list"])
        guard let rows = result as? [[String: Any]] else { return [] }
        var lights: [HALight] = []
        for row in rows {
            guard let entityId = row["entity_id"] as? String, entityId.hasPrefix("light.") else { continue }
            let platform = row["platform"] as? String
            let unique = row["unique_id"] as? String ?? ""
            if localtuyaOnly {
                let ok = platform == "localtuya" || unique.hasPrefix("local_") || entityId.contains("zone")
                if !ok { continue }
            }
            let name = (row["name"] as? String) ?? (row["original_name"] as? String) ?? entityId
            lights.append(HALight(entityId: entityId, name: name, platform: platform))
        }
        return lights.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func setLightRGB(entityId: String, rgb: RGB) async throws {
        guard !entityId.isEmpty else { return }
        _ = try await sendCommand([
            "type": "call_service",
            "domain": "light",
            "service": "turn_on",
            "target": ["entity_id": entityId],
            "service_data": [
                "rgb_color": [rgb.r, rgb.g, rgb.b],
                "brightness": max(rgb.r, rgb.g, rgb.b, 1),
            ],
        ])
    }

    public func turnOff(entityId: String) async throws {
        guard !entityId.isEmpty else { return }
        _ = try await sendCommand([
            "type": "call_service",
            "domain": "light",
            "service": "turn_off",
            "target": ["entity_id": entityId],
        ])
    }

    private func sendCommand(_ body: [String: Any]) async throws -> Any {
        let id = nextId
        nextId += 1
        var payload = body
        payload["id"] = id
        let data: Data = try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            Task {
                do { try await self.sendRaw(payload) }
                catch {
                    let c = self.pending.removeValue(forKey: id)
                    c?.resume(throwing: error)
                }
            }
        }
        let obj = try decode(data)
        if obj["success"] as? Bool == false {
            let err = (obj["error"] as? [String: Any])?["message"] as? String ?? "command failed"
            throw HAClientError.unexpected(err)
        }
        return obj["result"] as Any
    }

    private func sendRaw(_ object: [String: Any]) async throws {
        guard let task else { throw HAClientError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HAClientError.unexpected("utf8")
        }
        try await task.send(.string(text))
    }

    private func waitAuthMessage() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            authContinuation = cont
        }
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HAClientError.unexpected("json")
        }
        return obj
    }

    private func readLoop() async {
        guard let task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d):
                    guard let s = String(data: d, encoding: .utf8) else { continue }
                    text = s
                @unknown default: continue
                }
                guard let data = text.data(using: .utf8) else { continue }
                handle(data)
            } catch {
                break
            }
        }
    }

    private func handle(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = obj["type"] as? String
        if type == "auth_required" || type == "auth_ok" || type == "auth_invalid" {
            let cont = authContinuation
            authContinuation = nil
            cont?.resume(returning: data)
            return
        }
        if let id = obj["id"] as? Int, let cont = pending.removeValue(forKey: id) {
            cont.resume(returning: data)
        }
    }
}
