import Foundation

/// Vendors known to the core. New vendors add a case plus a DiscoveryProvider and driver.
public enum Vendor: String, Sendable, CaseIterable, Hashable {
    case wiz = "WiZ"
    case cozyLife = "CozyLife"

    public var displayName: String { rawValue }
}

public struct RGBColor: Equatable, Hashable, Sendable {
    public var red: Int
    public var green: Int
    public var blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Snapshot of a device. Every field is optional: `nil` means "the device did not report it".
public struct DeviceState: Equatable, Sendable {
    public var isOn: Bool?
    /// Brightness in percent (0...100).
    public var brightness: Int?
    public var color: RGBColor?
    /// Color temperature in Kelvin.
    public var colorTemperature: Int?

    public init(isOn: Bool? = nil, brightness: Int? = nil, color: RGBColor? = nil, colorTemperature: Int? = nil) {
        self.isOn = isOn
        self.brightness = brightness
        self.color = color
        self.colorTemperature = colorTemperature
    }
}

public struct DeviceCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let power = DeviceCapabilities(rawValue: 1 << 0)
    public static let brightness = DeviceCapabilities(rawValue: 1 << 1)
    public static let color = DeviceCapabilities(rawValue: 1 << 2)
    public static let colorTemperature = DeviceCapabilities(rawValue: 1 << 3)
}

public enum SmartDeviceError: Error, Equatable, Sendable {
    case unsupported(String)
    case timeout
    case invalidResponse(String)
    case transport(String)
}

/// Common interface every vendor driver implements. The UI and CLI depend only on this.
public protocol SmartDevice: Sendable {
    var id: String { get }
    var vendor: Vendor { get }
    var address: String { get }
    var name: String { get }
    var capabilities: DeviceCapabilities { get }

    func getState() async throws -> DeviceState
    func turnOn() async throws
    func turnOff() async throws
    func setBrightness(_ percent: Int) async throws
    func setColor(_ color: RGBColor) async throws
    func setColorTemperature(_ kelvin: Int) async throws
}
