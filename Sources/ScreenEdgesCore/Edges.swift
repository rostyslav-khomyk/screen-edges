public struct RGB: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public struct EdgeColors: Equatable, Sendable {
    public var left: RGB
    public var top: RGB
    public var right: RGB
    public var bottom: RGB

    public init(left: RGB, top: RGB, right: RGB, bottom: RGB) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// Hyperion LED order. Index 0 is the left edge.
    public var leds: [RGB] { [left, top, right, bottom] }
}

public enum EdgeName: String, CaseIterable, Sendable {
    case left, top, right, bottom
}

/// Row 0 of `rgb` is the top of the screen. `rgb` is packed RGB, 3 bytes per pixel.
public func sampleEdges(_ rgb: [UInt8], width: Int, height: Int) -> EdgeColors {
    let bandY = max(2, Int((Double(height) * 0.12).rounded()))
    let bandX = max(2, Int((Double(width) * 0.08).rounded()))
    func avg(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> RGB {
        var r = 0
        var g = 0
        var b = 0
        var n = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 3
                r += Int(rgb[i])
                g += Int(rgb[i + 1])
                b += Int(rgb[i + 2])
                n += 1
            }
        }
        guard n > 0 else { return RGB(0, 0, 0) }
        return RGB(r / n, g / n, b / n)
    }
    return EdgeColors(
        left: lift(avg(0, bandY, bandX, height - bandY)),
        top: lift(avg(0, 0, width, bandY)),
        right: lift(avg(width - bandX, bandY, width, height - bandY)),
        bottom: lift(avg(0, height - bandY, width, height))
    )
}

public func lift(_ rgb: RGB) -> RGB {
    let maxChannel = max(rgb.r, rgb.g, rgb.b)
    if maxChannel < 12 { return RGB(0, 0, 0) }
    let scaled = [rgb.r, rgb.g, rgb.b].map { Int((Double($0) * 255 / Double(maxChannel)).rounded()) }
    let scaledMin = scaled.min() ?? 0
    let span = 255 - scaledMin
    if span < 25 { return RGB(255, 255, 255) }
    let floor = Int((Double(scaledMin) * 0.2).rounded())
    let out = scaled.map { channel in
        Int((Double(floor) + Double(channel - scaledMin) * Double(255 - floor) / Double(span)).rounded())
    }
    return RGB(out[0], out[1], out[2])
}
