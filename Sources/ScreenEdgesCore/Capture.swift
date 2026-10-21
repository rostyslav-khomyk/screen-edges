import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum CaptureError: Error {
    case noDisplay
}

public struct FrameRGB: Sendable {
    public var bytes: [UInt8]
    public var width: Int
    public var height: Int
}

/// Grabs the widest display as a small RGB buffer for edge sampling.
public func captureEdgeFrame() async throws -> FrameRGB {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let display = content.displays.max(by: { $0.width < $1.width }) else {
        throw CaptureError.noDisplay
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let streamConfig = SCStreamConfiguration()
    streamConfig.width = 160
    streamConfig.height = max(1, Int((Double(display.height) / Double(display.width) * 160).rounded()))
    streamConfig.showsCursor = false
    streamConfig.capturesAudio = false
    streamConfig.queueDepth = 1
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: streamConfig)
    return rgbBuffer(image)
}

private func rgbBuffer(_ image: CGImage) -> FrameRGB {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
    rgba.withUnsafeMutableBytes { raw in
        if let ctx = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) {
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    var j = 0
    var i = 0
    while i + 2 < rgba.count && j + 2 < rgb.count {
        rgb[j] = rgba[i]
        rgb[j + 1] = rgba[i + 1]
        rgb[j + 2] = rgba[i + 2]
        j += 3
        i += 4
    }
    return FrameRGB(bytes: rgb, width: width, height: height)
}
