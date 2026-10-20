import Foundation

public struct DaemonConfig: Codable, Equatable, Sendable {
    public var token: String
    public var websocketPort: UInt16
    public var jsonPort: UInt16
    public var interval: Double

    public init(token: String, websocketPort: UInt16 = 8090, jsonPort: UInt16 = 19444, interval: Double = 0.125) {
        self.token = token
        self.websocketPort = websocketPort
        self.jsonPort = jsonPort
        self.interval = interval
    }

    public static func load(from url: URL) throws -> DaemonConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DaemonConfig.self, from: data)
    }
}
