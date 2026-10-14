import Foundation

public enum WiZDeviceError: Error, Equatable, Sendable {
    case invalidBrightness(Int)
    case invalidColor(RGBColor)
    case invalidTemperature(Int)
}

/// A connected WiZ driver. Connection queries configuration only; state is never cached.
public struct WiZDevice: SmartDevice {
    public let id: String
    public let vendor: Vendor = .wiz
    public let address: String
    public let name: String
    public let capabilities: DeviceCapabilities
    public let temperatureRange: ClosedRange<Int>?
    private let transport: any UDPTransport
    private static let timeout: TimeInterval = 1.5

    private init(_ device: DiscoveredDevice, system: WiZCodec.SystemInfo,
                 temperatureRange: ClosedRange<Int>?, transport: any UDPTransport) {
        id = device.identifier
        address = device.address
        name = system.moduleName ?? device.model ?? "WiZ \(device.identifier)"
        self.temperatureRange = temperatureRange
        self.transport = transport
        var supported: DeviceCapabilities = [.power, .brightness]
        // pywizlight BulbType.from_data inspects the second underscore-separated component.
        let components = (system.moduleName ?? "").split(separator: "_", omittingEmptySubsequences: false)
        if components.count > 1, components[1].contains("RGB") { supported.insert(.color) }
        if temperatureRange != nil { supported.insert(.colorTemperature) }
        capabilities = supported
    }

    public static func connect(_ device: DiscoveredDevice,
                               transport: any UDPTransport = BSDUDPTransport()) async throws -> WiZDevice {
        guard device.vendor == .wiz else { throw SmartDeviceError.unsupported("Not a WiZ device") }
        guard let data = try await transport.request(WiZCodec.getSystemConfig(), host: device.address,
                                                    port: WiZCodec.port, timeout: timeout) else {
            throw SmartDeviceError.timeout
        }
        guard let system = WiZCodec.parseSystemConfig(data) else {
            throw SmartDeviceError.invalidResponse("getSystemConfig")
        }
        let model = try await transport.request(WiZCodec.getModelConfig(), host: device.address,
                                                port: WiZCodec.port, timeout: timeout)
        var range = model.flatMap { WiZCodec.parseTemperatureRange($0, method: "getModelConfig") }
        if range == nil {
            let user = try await transport.request(WiZCodec.getUserConfig(), host: device.address,
                                                   port: WiZCodec.port, timeout: timeout)
            range = user.flatMap { WiZCodec.parseTemperatureRange($0, method: "getUserConfig") }
        }
        return WiZDevice(device, system: system, temperatureRange: range, transport: transport)
    }

    public func getState() async throws -> DeviceState {
        let data = try await request(WiZCodec.getPilot())
        guard let state = WiZCodec.parsePilot(data), state != DeviceState() else {
            throw SmartDeviceError.invalidResponse("getPilot")
        }
        return state
    }

    public func turnOn() async throws { try await setPilot(["state": true]) }
    public func turnOff() async throws { try await setPilot(["state": false]) }

    /// Zero is OFF; nonzero values use WiZ's 1...100 percentage (not 0...255).
    public func setBrightness(_ percent: Int) async throws {
        guard (0...100).contains(percent) else { throw WiZDeviceError.invalidBrightness(percent) }
        if percent == 0 { try await turnOff() }
        else { try await setPilot(["state": true, "dimming": percent]) }
    }

    /// Direct channel semantics, intentionally not pywizlight's perceptual RGB transform.
    public func setColor(_ color: RGBColor) async throws {
        guard capabilities.contains(.color) else { throw SmartDeviceError.unsupported("RGB color") }
        guard [color.red, color.green, color.blue].allSatisfy({ (0...255).contains($0) }) else {
            throw WiZDeviceError.invalidColor(color)
        }
        try await setPilot(["state": true, "r": color.red, "g": color.green, "b": color.blue, "c": 0, "w": 0])
    }

    public func setColorTemperature(_ kelvin: Int) async throws {
        guard let range = temperatureRange else { throw SmartDeviceError.unsupported("Color temperature") }
        guard range.contains(kelvin) else { throw WiZDeviceError.invalidTemperature(kelvin) }
        try await setPilot(["state": true, "temp": kelvin])
    }

    private func setPilot(_ params: [String: Any]) async throws {
        let data = try await request(WiZCodec.setPilot(params))
        guard WiZCodec.parseSetPilotACK(data) else { throw SmartDeviceError.invalidResponse("setPilot") }
    }

    private func request(_ payload: Data) async throws -> Data {
        guard let data = try await transport.request(payload, host: address, port: WiZCodec.port,
                                                    timeout: Self.timeout) else { throw SmartDeviceError.timeout }
        return data
    }
}
