import XCTest
@testable import ScreenEdgesCore

final class CoreTests: XCTestCase {
    func testTopRowIsTheTopEdge() {
        let width = 20
        let height = 10
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        func paint(_ x: Int, _ y: Int, _ color: (UInt8, UInt8, UInt8)) {
            let i = (y * width + x) * 3
            rgb[i] = color.0
            rgb[i + 1] = color.1
            rgb[i + 2] = color.2
        }
        for y in 0..<height {
            for x in 0..<width {
                if y < 2 { paint(x, y, (255, 0, 0)) }
                else if y >= 8 { paint(x, y, (0, 0, 255)) }
                else if x < 2 { paint(x, y, (255, 255, 0)) }
                else if x >= 18 { paint(x, y, (0, 255, 0)) }
            }
        }
        let edges = sampleEdges(rgb, width: width, height: height)
        XCTAssertEqual(edges.top, RGB(255, 0, 0))
        XCTAssertEqual(edges.bottom, RGB(0, 0, 255))
        XCTAssertEqual(edges.left, RGB(255, 255, 0))
        XCTAssertEqual(edges.right, RGB(0, 255, 0))
    }

    func testLiftPunchesAWeakBlue() {
        XCTAssertEqual(lift(RGB(40, 80, 160)), RGB(13, 94, 255))
    }

    func testLoginAndStream() {
        let session = HyperionSession(token: "test-token")
        let denied = session.handle(#"{"command":"serverinfo","tan":1}"#)
        XCTAssertTrue(denied?.json.contains("No authorization") == true)

        let login = session.handle(#"{"command":"authorize","subcommand":"login","token":"test-token","tan":2}"#)
        XCTAssertTrue(login?.json.contains("\"success\":true") == true)
        XCTAssertTrue(session.authorized)

        let info = session.handle(#"{"command":"serverinfo","subcommand":"getInfo","tan":3}"#)
        XCTAssertTrue(info?.json.contains("\"name\":\"left\"") == true)
        XCTAssertTrue(info?.json.contains("\"name\":\"bottom\"") == true)

        XCTAssertNil(session.streamUpdate(EdgeColors(left: RGB(1, 0, 0), top: RGB(0, 1, 0), right: RGB(0, 0, 1), bottom: RGB(1, 1, 0))))
        _ = session.handle(#"{"command":"ledcolors","subcommand":"ledstream-start","tan":4}"#)
        XCTAssertTrue(session.streaming)
        let update = session.streamUpdate(EdgeColors(left: RGB(9, 0, 0), top: RGB(0, 8, 0), right: RGB(0, 0, 7), bottom: RGB(1, 1, 1)))
        XCTAssertTrue(update?.contains("ledcolors-ledstream-update") == true)
        XCTAssertTrue(update?.contains("[9,0,0]") == true)
    }

    func testBadTokenDoesNotAuthorize() {
        let session = HyperionSession(token: "secret")
        _ = session.handle(#"{"command":"authorize","subcommand":"login","token":"nope","tan":1}"#)
        XCTAssertFalse(session.authorized)
    }
}
