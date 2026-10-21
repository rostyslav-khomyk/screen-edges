import Foundation

public struct EdgeMapping: Codable, Equatable, Sendable {
    public var left: String
    public var top: String
    public var right: String
    public var bottom: String

    public init(left: String = "", top: String = "", right: String = "", bottom: String = "") {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public func entity(for edge: EdgeName) -> String {
        switch edge {
        case .left: return left
        case .top: return top
        case .right: return right
        case .bottom: return bottom
        }
    }

    public mutating func set(_ edge: EdgeName, entityId: String) {
        switch edge {
        case .left: left = entityId
        case .top: top = entityId
        case .right: right = entityId
        case .bottom: bottom = entityId
        }
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var haURL: String
    public var haToken: String
    public var interval: Double
    public var enabled: Bool
    public var edges: EdgeMapping
    /// When true, only offer lights whose entity_id or name suggests localtuya zones.
    public var localtuyaOnly: Bool

    public init(
        haURL: String = "http://192.168.2.5",
        haToken: String = "",
        interval: Double = 0.15,
        enabled: Bool = false,
        edges: EdgeMapping = EdgeMapping(),
        localtuyaOnly: Bool = true
    ) {
        self.haURL = haURL
        self.haToken = haToken
        self.interval = interval
        self.enabled = enabled
        self.edges = edges
        self.localtuyaOnly = localtuyaOnly
    }

    enum CodingKeys: String, CodingKey {
        case haURL = "ha_url"
        case haToken = "ha_token"
        case interval, enabled, edges
        case localtuyaOnly = "localtuya_only"
    }

    public static func defaultURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/ScreenEdges/config.json")
    }

    public static func load(from url: URL = defaultURL()) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save(to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
