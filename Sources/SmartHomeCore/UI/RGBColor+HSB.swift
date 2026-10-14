import Foundation

public extension RGBColor {
    /// Full-brightness color from a hue/saturation position (for example a color wheel).
    /// Hue wraps around 0...1; saturation is clamped to 0...1. Non-finite input yields white.
    init(hue: Double, saturation: Double) {
        let h = hue.isFinite ? hue - hue.rounded(.down) : 0
        let s = saturation.isFinite ? min(max(saturation, 0), 1) : 0
        let sector = h * 6
        let fraction = sector - sector.rounded(.down)
        let low = 1 - s
        let falling = 1 - s * fraction
        let rising = 1 - s * (1 - fraction)
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (r, g, b) = (1, rising, low)
        case 1: (r, g, b) = (falling, 1, low)
        case 2: (r, g, b) = (low, 1, rising)
        case 3: (r, g, b) = (low, falling, 1)
        case 4: (r, g, b) = (rising, low, 1)
        default: (r, g, b) = (1, low, falling)
        }
        self.init(red: Int((r * 255).rounded()), green: Int((g * 255).rounded()),
                  blue: Int((b * 255).rounded()))
    }
}
