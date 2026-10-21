import Foundation
import ScreenEdgesCore

@main
struct StreamFixture {
    static func main() async throws {
        let control = CommandLine.arguments.contains("--control")
        let settings: AppConfig
        if control {
            settings = try JSONDecoder().decode(AppConfig.self, from: FileHandle.standardInput.readDataToEndOfFile())
        } else {
            settings = AppConfig(streamToken: "local-integration-test-token")
        }
        let server = HyperionServer(token: settings.streamToken)
        let port = try await server.start(port: 0)
        try output("PORT=\(port)")
        let publisher = Task {
            for _ in 0..<2400 {
                server.publish((0..<80).map { RGB($0, 255 - $0, ($0 * 3) % 256) })
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        if control {
            let client = HomeAssistantClient()
            try await client.connect(urlString: settings.haURL, token: settings.haToken)
            let layout = try await client.syncLayout()
            guard layout.zones.count == 4 else { throw HAClientError.unexpected("Missing fixture zones") }
            try await client.startStream(config: settings, port: port)
            try output("STARTED")
            try await Task.sleep(for: .milliseconds(300))
            try await client.stopStream(owner: settings.ownerID)
            try output("RELEASED")
            publisher.cancel()
        } else {
            try await publisher.value
        }
        server.stop()
    }

    static func output(_ line: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data("\(line)\n".utf8))
    }
}
