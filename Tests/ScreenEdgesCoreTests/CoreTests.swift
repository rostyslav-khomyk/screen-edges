import XCTest
import CoreGraphics
@testable import ScreenEdgesCore

final class CoreTests: XCTestCase {
    func testCapturePreservesImageRows() throws {
        let width = 20, height = 10
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i] = y < height / 2 ? 255 : 0
                rgba[i + 2] = y < height / 2 ? 0 : 255
            }
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                            bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        let frame = rgbBuffer(image)
        let edges = sampleEdges(frame.bytes, width: width, height: height)
        XCTAssertEqual(edges.top, RGB(255, 0, 0))
        XCTAssertEqual(edges.bottom, RGB(0, 0, 255))
    }

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
        XCTAssertEqual(lift(RGB(40, 80, 160)), RGB(8, 90, 255))
    }

    func testLiftKeepsGrayOffWhite() {
        XCTAssertEqual(lift(RGB(30, 30, 30)), RGB(75, 75, 75))
        XCTAssertEqual(lift(RGB(4, 4, 4)), RGB(0, 0, 0))
    }

    func testAppConfigRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screen-edges-test.json")
        var config = AppConfig(haURL: "http://192.168.2.5", haToken: "secret", enabled: true)
        config.edges.left = "light.monitor_zone_1"
        config.edges.bottom = "light.desk_zone_1"
        try config.save(to: url)
        let loaded = try AppConfig.load(from: url)
        XCTAssertEqual(loaded.haURL, "http://192.168.2.5")
        XCTAssertEqual(loaded.haToken, "secret")
        XCTAssertEqual(loaded.edges.left, "light.monitor_zone_1")
        XCTAssertEqual(loaded.edges.bottom, "light.desk_zone_1")
        try? FileManager.default.removeItem(at: url)
    }
}
