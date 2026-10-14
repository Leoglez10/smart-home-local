import Foundation
import Testing
@testable import SmartHomeCore

/// Each test owns a socket-free, ordered reply queue and request log.
private actor DriverUDPTransport: UDPTransport {
    struct Packet: Sendable {
        let payload: Data
        let host: String
        let port: UInt16
        let timeout: TimeInterval
    }
    private var replies: [Data?]
    private let failureAt: Int?
    private(set) var packets: [Packet] = []

    init(_ replies: [String?], failureAt: Int? = nil) {
        self.replies = replies.map { $0.map { Data($0.utf8) } }
        self.failureAt = failureAt
    }

    func broadcast(_ payload: Data, port: UInt16, sends: Int, interval: TimeInterval, listen: TimeInterval) async throws -> [Datagram] {
        Issue.record("Driver must never broadcast")
        return []
    }

    func request(_ payload: Data, host: String, port: UInt16, timeout: TimeInterval) async throws -> Data? {
        packets.append(Packet(payload: payload, host: host, port: port, timeout: timeout))
        if packets.count == failureAt { throw SmartDeviceError.transport("fixture failure") }
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}

private let driverSystem = #"{"method":"getSystemConfig","result":{"moduleName":"ESP01_SHRGB1C_31","fwVersion":"1.35.0","drvConf":[33,1]}}"#
private let driverModel = #"{"method":"getModelConfig","result":{"cctRange":[2200,2699,6500,6500],"nowc":1,"wcr":33}}"#
private let driverACK = #"{"method":"setPilot","result":{"success":true}}"#
private let driverDiscovery = DiscoveredDevice(
    vendor: .wiz, address: "192.0.2.7", identifier: "fixture-id", model: nil,
    state: DeviceState(isOn: false, brightness: 10))

private func packetObject(_ packet: DriverUDPTransport.Packet) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: packet.payload) as? [String: Any])
}

@Suite struct WiZDriverTests {
    @Test func connectIsReadOnlyAndAdvertisesVerifiedCapabilities() async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        let abstract: any SmartDevice = device
        #expect(abstract.id == "fixture-id")
        #expect(abstract.vendor == .wiz)
        #expect(abstract.address == "192.0.2.7")
        #expect(abstract.name == "ESP01_SHRGB1C_31")
        #expect(abstract.capabilities == [.power, .brightness, .color, .colorTemperature])
        #expect(device.temperatureRange == 2200...6500)
        let packets = await transport.packets
        #expect(try packets.map { try packetObject($0)["method"] as? String } == ["getSystemConfig", "getModelConfig"])
        #expect(try packets.allSatisfy { (try packetObject($0)["params"] as? [String: Any])?.isEmpty == true })
        #expect(packets.allSatisfy { $0.host == driverDiscovery.address && $0.port == 38899 && $0.timeout > 0 })
    }

    @Test(arguments: ["cctRange", "extRange", "whiteRange"])
    func rangesUseAdvertisedMinMaxAndUserFallback(_ key: String) async throws {
        let range = "{\"method\":\"getUserConfig\",\"result\":{\"\(key)\":[5000,3000,4000,3000]}}"
        let transport = DriverUDPTransport([driverSystem, #"{"method":"getModelConfig","result":{}}"#, range])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        #expect(device.temperatureRange == 3000...5000)
        #expect(device.capabilities.contains(.colorTemperature))
        let packets = await transport.packets
        #expect(try packets.map { try packetObject($0)["method"] as? String } == ["getSystemConfig", "getModelConfig", "getUserConfig"])
    }

    @Test(arguments: ["cctRange", "extRange", "whiteRange"])
    func modelRangeUsesMinMaxWithoutDefaults(_ key: String) async throws {
        let config = "{\"method\":\"getModelConfig\",\"result\":{\"\(key)\":[5000,3000,4000,3000]}}"
        let transport = DriverUDPTransport([driverSystem, config])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        #expect(device.temperatureRange == 3000...5000)
        #expect(await transport.packets.count == 2)
    }

    @Test(arguments: [nil, "not json", #"{"method":"getModelConfig","result":{}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":[2200]}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":[0,6500]}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":[2200,2200]}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":[true,6500]}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":[2200.5,6500]}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":["2200",6500]}}"#,
                      #"{"method":"getPilot","result":{"cctRange":[2200,6500]}}"#,
                      #"{"method":"getModelConfig","result":{"cctRange":[2200,6500]},"error":{"code":-1}}"#] as [String?])
    func unknownOrMalformedRangeFailsClosed(_ config: String?) async throws {
        let transport = DriverUDPTransport([driverSystem, config, nil])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        #expect(device.temperatureRange == nil)
        #expect(!device.capabilities.contains(.colorTemperature))
        await #expect(throws: SmartDeviceError.unsupported("Color temperature")) { try await device.setColorTemperature(3714) }
        #expect(await transport.packets.count == 3)
    }

    @Test(arguments: [#"{"method":"getSystemConfig","result":{}}"#,
                      #"{"method":"getSystemConfig","result":{"moduleName":"unknown"}}"#,
                      #"{"method":"getSystemConfig","result":{"moduleName":"RGB_UNKNOWN"}}"#,
                      #"{"method":"getSystemConfig","result":{"moduleName":"ESP01_SHDW_31"}}"#])
    func unknownOrWhiteOnlyModulesDoNotAdvertiseRGB(_ system: String) async throws {
        let transport = DriverUDPTransport([system, driverModel])
        var discovered = driverDiscovery
        discovered.model = "ESP01_SHRGB1C_31" // stale discovery must not enable unsupported writes
        let device = try await WiZDevice.connect(discovered, transport: transport)
        #expect(!device.capabilities.contains(.color))
        await #expect(throws: SmartDeviceError.unsupported("RGB color")) {
            try await device.setColor(RGBColor(red: 255, green: 0, blue: 0))
        }
        #expect(await transport.packets.count == 2)
    }

    @Test func missingModelNameUsesWiZIdentifier() async throws {
        let transport = DriverUDPTransport([#"{"method":"getSystemConfig","result":{}}"#, nil, nil])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        #expect(device.name == "WiZ fixture-id")
        #expect(device.capabilities == [.power, .brightness])
    }

    @Test func wrongVendorRejectedBeforeAnyPacket() async throws {
        let transport = DriverUDPTransport([])
        var discovered = driverDiscovery
        discovered.vendor = .cozyLife
        await #expect(throws: SmartDeviceError.unsupported("Not a WiZ device")) {
            try await WiZDevice.connect(discovered, transport: transport)
        }
        #expect(await transport.packets.isEmpty)
    }

    @Test func systemTimeoutFailsConnection() async throws {
        let transport = DriverUDPTransport([nil])
        await #expect(throws: SmartDeviceError.timeout) { try await WiZDevice.connect(driverDiscovery, transport: transport) }
        #expect(await transport.packets.count == 1)
    }

    @Test(arguments: ["bad json", #"{"method":"getPilot","result":{}}"#,
                      #"{"method":"getSystemConfig","error":{"code":-1}}"#])
    func malformedSystemFailsConnection(_ reply: String) async throws {
        let transport = DriverUDPTransport([reply])
        await #expect(throws: SmartDeviceError.invalidResponse("getSystemConfig")) {
            try await WiZDevice.connect(driverDiscovery, transport: transport)
        }
        #expect(await transport.packets.count == 1)
    }

    @Test func getStateTimeoutDoesNotReturnDiscoverySnapshot() async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, nil])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: SmartDeviceError.timeout) { try await device.getState() }
    }

    @Test(arguments: ["bad json", #"{"method":"setPilot","result":{"success":true}}"#,
                      #"{"method":"getPilot","error":{"code":-1}}"#,
                      #"{"method":"getPilot","result":{}}"#,
                      #"{"method":"getPilot","result":{"state":1}}"#,
                      #"{"method":"getPilot","result":{"state":true,"dimming":"83"}}"#,
                      #"{"method":"getPilot","result":{"state":true,"dimming":true}}"#,
                      #"{"method":"getPilot","result":{"state":true,"dimming":101}}"#,
                      #"{"method":"getPilot","result":{"state":true,"r":256,"g":0,"b":0}}"#])
    func malformedPilotDoesNotReturnInventedState(_ reply: String) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, reply])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: SmartDeviceError.invalidResponse("getPilot")) { try await device.getState() }
    }

    @Test func sparsePilotKeepsUnreportedFieldsNil() async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, #"{"method":"getPilot","result":{"state":false}}"#])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        #expect(try await device.getState() == DeviceState(isOn: false))
    }

    @Test(arguments: [1, 2, 3]) func connectPropagatesTransportErrors(_ requestNumber: Int) async {
        let transport = DriverUDPTransport([driverSystem, nil], failureAt: requestNumber)
        await #expect(throws: SmartDeviceError.transport("fixture failure")) {
            try await WiZDevice.connect(driverDiscovery, transport: transport)
        }
        #expect(await transport.packets.count == requestNumber)
    }

    @Test(arguments: DriverOperation.allCases) func settersPropagateTransportErrors(_ operation: DriverOperation) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel], failureAt: 3)
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: SmartDeviceError.transport("fixture failure")) { try await operation.run(device) }
        #expect(await transport.packets.count == 3)
    }

    @Test func getStatePropagatesTransportError() async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel], failureAt: 3)
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: SmartDeviceError.transport("fixture failure")) { try await device.getState() }
    }

    @Test func powerUsesAbsoluteBooleanState() async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, driverACK, driverACK])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        try await device.turnOn()
        try await device.turnOff()
        let packets = await transport.packets
        try expectSetter(packets[2], params: ["state": true])
        try expectSetter(packets[3], params: ["state": false])
    }

    @Test(arguments: [1, 50, 100]) func brightnessUsesPercentAndTurnsOn(_ percent: Int) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, driverACK])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        try await device.setBrightness(percent)
        let packets = await transport.packets
        try expectSetter(packets[2], params: ["state": true, "dimming": percent])
    }

    @Test func zeroBrightnessMeansOffNotZeroDimming() async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, driverACK])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        try await device.setBrightness(0)
        let packets = await transport.packets
        try expectSetter(packets[2], params: ["state": false])
    }

    @Test(arguments: [-1, 101, Int.min, Int.max]) func invalidBrightnessSendsNothing(_ percent: Int) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: WiZDeviceError.invalidBrightness(percent)) { try await device.setBrightness(percent) }
        #expect(await transport.packets.count == 2)
    }

    @Test(arguments: [RGBColor(red: 255, green: 0, blue: 0), RGBColor(red: 0, green: 255, blue: 255), RGBColor(red: 0, green: 0, blue: 0)])
    func rgbUsesDirectChannelsAndClearsWhite(_ color: RGBColor) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, driverACK])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        try await device.setColor(color)
        let packets = await transport.packets
        try expectSetter(packets[2], params: ["state": true, "r": color.red, "g": color.green, "b": color.blue, "c": 0, "w": 0])
    }

    @Test(arguments: [RGBColor(red: -1, green: 0, blue: 0), RGBColor(red: 256, green: 0, blue: 0),
                      RGBColor(red: 0, green: -1, blue: 0), RGBColor(red: 0, green: 256, blue: 0),
                      RGBColor(red: 0, green: 0, blue: -1), RGBColor(red: 0, green: 0, blue: 256)])
    func invalidRGBSendsNothing(_ color: RGBColor) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: WiZDeviceError.invalidColor(color)) { try await device.setColor(color) }
        #expect(await transport.packets.count == 2)
    }

    @Test(arguments: [2200, 3714, 6500]) func temperatureUsesAdvertisedKelvinRange(_ kelvin: Int) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, driverACK])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        try await device.setColorTemperature(kelvin)
        let packets = await transport.packets
        try expectSetter(packets[2], params: ["state": true, "temp": kelvin])
    }

    @Test(arguments: [2199, 6501, 0, Int.min, Int.max]) func invalidTemperatureSendsNothing(_ kelvin: Int) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: WiZDeviceError.invalidTemperature(kelvin)) { try await device.setColorTemperature(kelvin) }
        #expect(await transport.packets.count == 2)
    }

    @Test func getStateIsFreshAndNeverAnOptimisticCache() async throws {
        let transport = DriverUDPTransport([
            driverSystem, driverModel, driverACK,
            #"{"method":"getPilot","result":{"state":false,"temp":3714,"dimming":83,"sceneId":0}}"#,
            #"{"method":"getPilot","result":{"state":true,"dimming":50,"r":255,"g":0,"b":0}}"#,
        ])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        try await device.turnOn()
        #expect(try await device.getState() == DeviceState(isOn: false, brightness: 83, colorTemperature: 3714))
        #expect(try await device.getState() == DeviceState(isOn: true, brightness: 50, color: RGBColor(red: 255, green: 0, blue: 0)))
        let packets = await transport.packets
        #expect(try packets.map { try packetObject($0)["method"] as? String } == ["getSystemConfig", "getModelConfig", "setPilot", "getPilot", "getPilot"])
    }

    @Test(arguments: DriverOperation.allCases) func setterTimeoutIsNotSuccess(_ operation: DriverOperation) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, nil])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: SmartDeviceError.timeout) { try await operation.run(device) }
        #expect(await transport.packets.count == 3)
    }

    @Test(arguments: DriverOperation.allCases, [
        #"{"method":"setPilot","result":{"success":false}}"#,
        #"{"method":"setPilot","result":{}}"#,
        #"{"method":"setPilot","result":{"success":1}}"#,
        #"{"method":"setPilot","result":{"success":"true"}}"#,
        #"{"method":"getPilot","result":{"success":true}}"#,
        #"{"method":"setPilot","result":{"success":true},"error":{"code":-1}}"#,
        #"{"method":"setPilot","result":{"success":true},"error":null}"#,
        "not json",
    ])
    func rejectedOrMalformedACKIsNotSuccess(_ operation: DriverOperation, _ reply: String) async throws {
        let transport = DriverUDPTransport([driverSystem, driverModel, reply])
        let device = try await WiZDevice.connect(driverDiscovery, transport: transport)
        await #expect(throws: SmartDeviceError.invalidResponse("setPilot")) { try await operation.run(device) }
        #expect(await transport.packets.count == 3)
    }
}

private func expectSetter(_ packet: DriverUDPTransport.Packet, params: [String: Any]) throws {
    let object = try packetObject(packet)
    #expect(object["method"] as? String == "setPilot")
    let actual = try #require(object["params"] as? [String: Any])
    #expect(NSDictionary(dictionary: actual).isEqual(to: params))
    // NSDictionary bridges 1 and true as equal; explicitly protect the wire boolean type.
    let expectedState = try #require(params["state"] as? Bool)
    #expect(String(decoding: packet.payload, as: UTF8.self).contains("\"state\":\(expectedState)"))
    #expect(packet.host == driverDiscovery.address)
    #expect(packet.port == 38899)
}

enum DriverOperation: CaseIterable, Sendable {
    case on, off, brightness, color, temperature
    func run(_ device: WiZDevice) async throws {
        switch self {
        case .on: try await device.turnOn()
        case .off: try await device.turnOff()
        case .brightness: try await device.setBrightness(50)
        case .color: try await device.setColor(RGBColor(red: 255, green: 0, blue: 0))
        case .temperature: try await device.setColorTemperature(3714)
        }
    }
}
