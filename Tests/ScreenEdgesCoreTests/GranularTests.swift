import Foundation
import XCTest
@testable import ScreenEdgesCore

final class GranularTests: XCTestCase {
    func testSpatialGradientRetainsTwentyDistinctSamplesAcrossFullEdge() {
        let width = 200, height = 100
        var rgb: [UInt8] = []
        for _ in 0..<height {
            for x in 0..<width { rgb += [255, UInt8(x), 0] }
        }
        let frame = sampleGranularEdges(rgb, width: width, height: height)
        XCTAssertEqual(frame.count, 80)
        XCTAssertEqual(frame[20], RGB(255, 4, 0))
        XCTAssertEqual(frame[39], RGB(255, 194, 0))
        XCTAssertEqual(Set(frame[20..<40].map(\.g)).count, 20)
        XCTAssertEqual(Array(frame[20..<40]), Array(frame[60..<80]))
    }

    func testVerticalEdgesAreTopToBottom() {
        let width = 100, height = 200
        var rgb: [UInt8] = []
        for y in 0..<height {
            for _ in 0..<width { rgb += [0, UInt8(y), 255] }
        }
        let frame = sampleGranularEdges(rgb, width: width, height: height)
        XCTAssertEqual(frame.first, RGB(0, 4, 255))
        XCTAssertEqual(frame[19], RGB(0, 194, 255))
        XCTAssertEqual(Array(frame[0..<20]), Array(frame[40..<60]))
    }

    func testTinyAndInvalidBuffers() {
        XCTAssertEqual(sampleGranularEdges([255, 0, 0], width: 1, height: 1), Array(repeating: RGB(255, 0, 0), count: 80))
        XCTAssertEqual(sampleGranularEdges([], width: 0, height: 10), [])
        XCTAssertEqual(sampleGranularEdges([1, 2], width: 1, height: 1), [])
    }

    func testLegacyConfigMigrationPreservesMappingAndCredentials() throws {
        let data = Data(#"{"ha_url":"http://example.test","ha_token":"private-test-token","enabled":true,"edges":{"left":"light.monitor_left","top":"light.monitor_top","right":"","bottom":"light.desk_bottom"}}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config.mappings.map(\.entityId), ["light.monitor_left", "light.monitor_top", "light.desk_bottom"])
        XCTAssertEqual(config.mappings.map(\.edge), [.left, .top, .bottom])
        XCTAssertEqual(config.haToken, "private-test-token")
        XCTAssertEqual(config.streamPort, 8090)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        var edited = config
        edited.mappings = []
        XCTAssertTrue(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(edited)).mappings.isEmpty)
    }

    func testSameEdgeCanMapToMultipleStripsWithIndependentDirection() throws {
        let config = AppConfig(mappings: [ZoneMapping(entityId: "light.monitor_left", edge: .left, reverse: true), ZoneMapping(entityId: "light.desk_left", edge: .left)])
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.mappings, config.mappings)
    }

    func testHyperionRejectsUnauthenticatedStreamingAndStopsAfterLogoutAttempt() throws {
        var session = HyperionSession(token: "test-secret-token")
        let frame = Array(repeating: RGB(1, 2, 3), count: 80)
        func command(_ text: String) -> Data { Data(text.utf8) }
        _ = session.handle(command(#"{"command":"ledcolors","subcommand":"ledstream-start"}"#))
        XCTAssertNil(session.frame(frame))
        _ = session.handle(command(#"{"command":"authorize","subcommand":"login","token":"test-secret-token"}"#))
        _ = session.handle(command(#"{"command":"ledcolors","subcommand":"ledstream-start"}"#))
        let data = try XCTUnwrap(session.frame(frame))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["command"] as? String, "ledcolors-ledstream-update")
        XCTAssertEqual(((body["data"] as? [String: Any])?["leds"] as? [[Int]])?.count, 80)
        _ = session.handle(command(#"{"command":"ledcolors","subcommand":"ledstream-stop"}"#))
        XCTAssertNil(session.frame(frame))
        _ = session.handle(command(#"{"command":"authorize","subcommand":"login","token":"wrong"}"#))
        XCTAssertFalse(session.authorized)
        XCTAssertFalse(session.streaming)
    }

    func testRealWebSocketServerSendsCachedFrameOnlyAfterAuthAndSubscription() async throws {
        let server = HyperionServer(token: "test-secret-token")
        let port = try await server.start(port: 0)
        server.publish((0..<80).map { RGB($0, 0, 255 - $0) })
        let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil); server.stop() }
        try await socket.send(.string(#"{"command":"authorize","subcommand":"login","token":"test-secret-token"}"#))
        let auth = try await socket.receive()
        guard case .string(let authText) = auth else { return XCTFail("Expected auth JSON") }
        XCTAssertTrue(authText.contains("true"))
        try await socket.send(.string(#"{"command":"ledcolors","subcommand":"ledstream-start"}"#))
        _ = try await socket.receive()
        let message = try await socket.receive()
        guard case .string(let text) = message else { return XCTFail("Expected frame JSON") }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let leds = try XCTUnwrap((body["data"] as? [String: Any])?["leds"] as? [[Int]])
        XCTAssertEqual(leds.first, [0, 0, 255])
        XCTAssertEqual(leds.last, [79, 0, 176])
    }
    func testMasterGateHonorsSelectedZonesAndLegacyLayouts() throws {
        let data = Data(#"{"protocol_version":1,"samples_per_edge":20,"owners":[],"zones":[{"entity_id":"light.monitor","name":"Monitor","device_name":"Strip","cm":110,"sections":20,"output_enabled":false},{"entity_id":"light.desk","name":"Desk","device_name":"Strip","cm":300,"sections":20}]}"#.utf8)
        let layout = try JSONDecoder().decode(HASyncLayout.self, from: data)
        XCTAssertFalse(layout.outputEnabled(for: [ZoneMapping(entityId: "light.monitor", edge: .top)]))
        XCTAssertTrue(layout.outputEnabled(for: [ZoneMapping(entityId: "light.desk", edge: .bottom)]))
        XCTAssertFalse(layout.outputEnabled(for: [ZoneMapping(entityId: "light.monitor", edge: .top), ZoneMapping(entityId: "light.desk", edge: .bottom)]))
        let enabled = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "false", with: "true").utf8)
        XCTAssertTrue(try JSONDecoder().decode(HASyncLayout.self, from: enabled).outputEnabled(for: [ZoneMapping(entityId: "light.monitor", edge: .top)]))
    }

}
