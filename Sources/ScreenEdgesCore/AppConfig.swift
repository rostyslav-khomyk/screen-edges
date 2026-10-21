import Foundation

public struct ZoneMapping: Codable, Equatable, Sendable, Identifiable {
    public var entityId: String
    public var edge: EdgeName
    public var reverse: Bool
    public var id: String { entityId }

    public init(entityId: String, edge: EdgeName, reverse: Bool = false) {
        self.entityId = entityId; self.edge = edge; self.reverse = reverse
    }

    enum CodingKeys: String, CodingKey { case entityId = "entity_id", edge, reverse }
}

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
    public var mappings: [ZoneMapping]
    public var streamPort: Int
    public var streamToken: String
    public var ownerID: String

    public init(
        haURL: String = "http://192.168.2.5",
        haToken: String = "",
        interval: Double = 0.15,
        enabled: Bool = false,
        edges: EdgeMapping = EdgeMapping(),
        localtuyaOnly: Bool = true,
        mappings: [ZoneMapping]? = nil,
        streamPort: Int = 8090,
        streamToken: String = UUID().uuidString,
        ownerID: String = UUID().uuidString
    ) {
        self.haURL = haURL
        self.haToken = haToken
        self.interval = interval
        self.enabled = enabled
        self.edges = edges
        self.localtuyaOnly = localtuyaOnly
        self.mappings = mappings ?? Self.migrate(edges)
        self.streamPort = streamPort
        self.streamToken = streamToken
        self.ownerID = ownerID
    }

    enum CodingKeys: String, CodingKey {
        case haURL = "ha_url"
        case haToken = "ha_token"
        case interval, enabled, edges
        case localtuyaOnly = "localtuya_only"
        case mappings, streamPort = "stream_port", streamToken = "stream_token", ownerID = "owner_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        haURL = try c.decode(String.self, forKey: .haURL)
        haToken = try c.decode(String.self, forKey: .haToken)
        interval = try c.decodeIfPresent(Double.self, forKey: .interval) ?? 0.15
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        edges = try c.decodeIfPresent(EdgeMapping.self, forKey: .edges) ?? EdgeMapping()
        localtuyaOnly = try c.decodeIfPresent(Bool.self, forKey: .localtuyaOnly) ?? true
        mappings = try c.decodeIfPresent([ZoneMapping].self, forKey: .mappings) ?? Self.migrate(edges)
        streamPort = try c.decodeIfPresent(Int.self, forKey: .streamPort) ?? 8090
        streamToken = try c.decodeIfPresent(String.self, forKey: .streamToken) ?? UUID().uuidString
        ownerID = try c.decodeIfPresent(String.self, forKey: .ownerID) ?? UUID().uuidString
    }

    private static func migrate(_ edges: EdgeMapping) -> [ZoneMapping] {
        var seen = Set<String>()
        return EdgeName.allCases.compactMap { edge in
            let id = edges.entity(for: edge)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return ZoneMapping(entityId: id, edge: edge)
        }
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
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
