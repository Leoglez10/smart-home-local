import Testing
import SmartHomeCore

private let hsbCases: [(Double, Double, RGBColor)] = [
        (0.0, 1.0, RGBColor(red: 255, green: 0, blue: 0)),
        (1.0 / 6, 1.0, RGBColor(red: 255, green: 255, blue: 0)),
        (1.0 / 3, 1.0, RGBColor(red: 0, green: 255, blue: 0)),
        (0.5, 1.0, RGBColor(red: 0, green: 255, blue: 255)),
        (2.0 / 3, 1.0, RGBColor(red: 0, green: 0, blue: 255)),
        (5.0 / 6, 1.0, RGBColor(red: 255, green: 0, blue: 255)),
        (0.0, 0.0, RGBColor(red: 255, green: 255, blue: 255)),
        (0.0, 0.5, RGBColor(red: 255, green: 128, blue: 128)),
]

@Suite struct RGBColorHSBTests {
    @Test(arguments: hsbCases)
    func convertsHueAndSaturationToRGB(hue: Double, saturation: Double, expected: RGBColor) {
        #expect(RGBColor(hue: hue, saturation: saturation) == expected)
    }

    @Test func wrapsHueAndClampsSaturationIntoValidChannels() {
        #expect(RGBColor(hue: 1.0, saturation: 1) == RGBColor(red: 255, green: 0, blue: 0))
        #expect(RGBColor(hue: -1.0 / 3, saturation: 1) == RGBColor(red: 0, green: 0, blue: 255))
        #expect(RGBColor(hue: 0, saturation: 5) == RGBColor(red: 255, green: 0, blue: 0))
        #expect(RGBColor(hue: 0, saturation: -1) == RGBColor(red: 255, green: 255, blue: 255))
        #expect(RGBColor(hue: .nan, saturation: .nan) == RGBColor(red: 255, green: 255, blue: 255))
    }
}
