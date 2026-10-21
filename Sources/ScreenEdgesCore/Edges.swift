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

    /// Edge order used when mapping to HA lights: left, top, right, bottom.
    public var leds: [RGB] { [left, top, right, bottom] }
}

public enum EdgeName: String, CaseIterable, Codable, Sendable {
    case left, top, right, bottom
}

/// Canonical Hyperion order: L/T/R/B, 20 samples each. Vertical edges run top
/// to bottom; horizontal edges run left to right, independently of strip wiring.
public func sampleGranularEdges(_ rgb: [UInt8], width: Int, height: Int) -> [RGB] {
    guard width > 0, height > 0, rgb.count == width * height * 3 else { return [] }
    let bandX = min(width, max(1, Int((Double(width) * 0.08).rounded())))
    let bandY = min(height, max(1, Int((Double(height) * 0.12).rounded())))
    func average(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> RGB {
        var sum = [0, 0, 0]
        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = (y * width + x) * 3
                for c in 0..<3 { sum[c] += Int(rgb[offset + c]) }
            }
        }
        let count = max(1, (x1 - x0) * (y1 - y0))
        return lift(RGB(sum[0] / count, sum[1] / count, sum[2] / count))
    }
    return EdgeName.allCases.flatMap { edge in
        (0..<20).map { index in
            let vertical = edge == .left || edge == .right
            let length = vertical ? height : width
            let start = min(length - 1, index * length / 20)
            let end = min(length, max(start + 1, (index + 1) * length / 20))
            switch edge {
            case .left: return average(0, start, bandX, end)
            case .top: return average(start, 0, end, bandY)
            case .right: return average(width - bandX, start, width, end)
            case .bottom: return average(start, height - bandY, end, height)
            }
        }
    }
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
    // A dark desktop is gray. Stretching that to full white floods the strip.
    // Dim colors get a limited boost. Gray stays gray. A real hue still gets punched.
    let gain = max(1.0, min(2.5, 160.0 / Double(maxChannel)))
    let boosted = [rgb.r, rgb.g, rgb.b].map { min(255, Int((Double($0) * gain).rounded())) }
    let high = boosted.max() ?? 0
    let low = boosted.min() ?? 0
    if high - low < 18 {
        return RGB(boosted[0], boosted[1], boosted[2])
    }
    let span = high - low
    let floor = low / 5
    let out = boosted.map { channel in
        floor + (channel - low) * (255 - floor) / span
    }
    return RGB(out[0], out[1], out[2])
}
