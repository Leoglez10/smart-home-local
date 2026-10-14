import Testing
@testable import SmartHomeCore

private let initialState = DeviceState(isOn: false, brightness: 83, colorTemperature: 3714)
private let stateReport = "Reachability: reachable\nState: OFF\nBrightness: 83%\nColor: unknown\nTemperature: 3714 K\n"
private let commandHelp = """
Commands:
  devices                 List controllable devices
  select <number>         Select a device from the numbered list
  on | off                Change power
  brightness <0...100>    Set brightness percent
  color <r> <g> <b>       Set RGB channels (0...255)
  temperature <kelvin>   Set verified color temperature
  status                  Read real device state
  help                    Show commands
  quit                    Exit

"""

/// Every test gets its own actor; there are no sockets or shared fake state.
private actor SessionFakeDevice: SmartDevice {
    nonisolated let id = "fixture-id"
    nonisolated let vendor = Vendor.wiz
    nonisolated let address = "192.0.2.7"
    nonisolated let name = "fixture-model"
    nonisolated let capabilities: DeviceCapabilities
    private(set) var state = initialState
    private(set) var writes: [String] = []
    private(set) var reads = 0
    private let writeFailure: SmartDeviceError?
    private let readFailure: SmartDeviceError?
    private let ignoreWrites: Bool

    init(capabilities: DeviceCapabilities = [.power, .brightness, .color, .colorTemperature],
         writeFailure: SmartDeviceError? = nil, readFailure: SmartDeviceError? = nil,
         ignoreWrites: Bool = false) {
        self.capabilities = capabilities
        self.writeFailure = writeFailure
        self.readFailure = readFailure
        self.ignoreWrites = ignoreWrites
    }

    func getState() async throws -> DeviceState {
        reads += 1
        if let readFailure { throw readFailure }
        return state
    }

    private func record(_ command: String) throws {
        writes.append(command)
        if let writeFailure { throw writeFailure }
    }

    func turnOn() async throws {
        try record("on")
        if !ignoreWrites { state.isOn = true }
    }

    func turnOff() async throws {
        try record("off")
        if !ignoreWrites { state.isOn = false }
    }

    func setBrightness(_ percent: Int) async throws {
        try record("brightness \(percent)")
        if !ignoreWrites { state.brightness = percent }
    }

    func setColor(_ color: RGBColor) async throws {
        try record("color \(color.red) \(color.green) \(color.blue)")
        if !ignoreWrites { state.color = color; state.colorTemperature = nil }
    }

    func setColorTemperature(_ kelvin: Int) async throws {
        try record("temperature \(kelvin)")
        if !ignoreWrites { state.colorTemperature = kelvin; state.color = nil }
    }
}

private func session(_ device: SessionFakeDevice) -> DeviceSession {
    DeviceSession(devices: [SessionDevice(device, temperatureRange: 2200...6500)])
}

@Suite struct DeviceSessionTests {
    @Test func listsModelAndIDWithoutInventedRoomNames() async {
        let device = SessionFakeDevice()
        var sut = session(device)
        #expect(await sut.execute("devices") == SessionResponse(
            output: "Devices\n1. [WiZ] fixture-model | ID: fixture-id | Address: 192.0.2.7\n"))
        #expect(await device.reads == 0)
        #expect(await device.writes.isEmpty)
    }

    @Test func emptyListIsExplicit() async {
        var sut = DeviceSession(devices: [])
        #expect(await sut.execute("devices") == SessionResponse(output: "Devices\n(no controllable devices found)\n"))
        #expect(await sut.execute("select 1") == SessionResponse(error: "error: device number out of range\n"))
    }

    @Test func selectionAndStatusReadRealState() async {
        let device = SessionFakeDevice()
        var sut = session(device)
        #expect(await sut.execute("select 1") == SessionResponse(output: "Selected 1: [WiZ] fixture-model (fixture-id)\n"))
        #expect(await sut.execute("status") == SessionResponse(output: stateReport))
        #expect(await device.reads == 1)
        #expect(await device.writes.isEmpty)
    }

    @Test(arguments: ["on", "off", "brightness 50", "color 255 0 0", "temperature 2700", "status"])
    func commandsRequireSelection(command: String) async {
        let device = SessionFakeDevice()
        var sut = session(device)
        #expect(await sut.execute(command) == SessionResponse(error: "error: no device selected; use select <number>\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
        #expect(await device.reads == 0)
    }

    @Test(arguments: [
        ("on", "on", "Reachability: reachable\nState: ON\nBrightness: 83%\nColor: unknown\nTemperature: 3714 K\n"),
        ("off", "off", stateReport),
        ("brightness 50", "brightness 50", "Reachability: reachable\nState: OFF\nBrightness: 50%\nColor: unknown\nTemperature: 3714 K\n"),
        ("color 255 0 0", "color 255 0 0", "Reachability: reachable\nState: OFF\nBrightness: 83%\nColor: 255 0 0\nTemperature: unknown\n"),
        ("temperature 2700", "temperature 2700", "Reachability: reachable\nState: OFF\nBrightness: 83%\nColor: unknown\nTemperature: 2700 K\n")
    ])
    func validCommandsWriteThenRead(command: String, write: String, output: String) async {
        let device = SessionFakeDevice()
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute(command) == SessionResponse(output: output))
        #expect(await device.writes == [write])
        #expect(await device.reads == 1)
    }

    @Test(arguments: [
        ("devices extra", "usage: devices"), ("select", "usage: select <number>"),
        ("select one", "usage: select <number>"), ("select 1 extra", "usage: select <number>"),
        ("on extra", "usage: on"), ("off extra", "usage: off"),
        ("brightness", "usage: brightness <0...100>"), ("brightness 1.5", "usage: brightness <0...100>"),
        ("brightness 50 extra", "usage: brightness <0...100>"),
        ("brightness -1", "brightness must be between 0 and 100"),
        ("brightness 101", "brightness must be between 0 and 100"),
        ("color 255 0", "usage: color <r> <g> <b>"),
        ("color 255 0 0 extra", "usage: color <r> <g> <b>"),
        ("color red 0 0", "usage: color <r> <g> <b>"),
        ("color 256 0 0", "color channels must be between 0 and 255"),
        ("color 0 -1 0", "color channels must be between 0 and 255"),
        ("temperature", "usage: temperature <kelvin>"),
        ("temperature warm", "usage: temperature <kelvin>"),
        ("temperature 2700 extra", "usage: temperature <kelvin>"),
        ("temperature 0", "temperature must be positive"),
        ("status extra", "usage: status"), ("help extra", "usage: help"),
        ("quit extra", "usage: quit"), ("unknown", "unknown command 'unknown'"),
        ("brightness 999999999999999999999999", "usage: brightness <0...100>")
    ])
    func malformedInputNeverReadsOrWrites(command: String, error: String) async {
        let device = SessionFakeDevice()
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute(command) == SessionResponse(error: "error: \(error)\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
        #expect(await device.reads == 0)
    }

    @Test(arguments: ["select 0", "select -1", "select 2"])
    func invalidSelectionPreservesPreviousSelection(command: String) async {
        let device = SessionFakeDevice()
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute(command) == SessionResponse(error: "error: device number out of range\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
        #expect(await sut.execute("status") == SessionResponse(output: stateReport))
    }

    @Test(arguments: [2199, 6501])
    func temperatureRespectsVerifiedRange(kelvin: Int) async {
        let device = SessionFakeDevice()
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute("temperature \(kelvin)") == SessionResponse(error: "error: temperature must be between 2200 and 6500 K\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
        #expect(await device.reads == 0)
    }

    @Test func temperatureWithoutVerifiedRangeCannotWrite() async {
        let device = SessionFakeDevice()
        var sut = DeviceSession(devices: [SessionDevice(device)])
        _ = await sut.execute("select 1")
        #expect(await sut.execute("temperature 2700") == SessionResponse(error: "error: verified temperature range unavailable\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
    }

    @Test(arguments: ["on", "off", "brightness 50", "color 255 0 0", "temperature 2700"])
    func unsupportedCapabilitiesCannotWrite(command: String) async {
        let device = SessionFakeDevice(capabilities: [])
        var sut = session(device)
        _ = await sut.execute("select 1")
        let feature = command.split(separator: " ").first!
        #expect(await sut.execute(command) == SessionResponse(error: "error: selected device does not support \(feature)\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
        #expect(await device.reads == 0)
    }

    @Test func successfulWriteDoesNotInventState() async {
        let device = SessionFakeDevice(ignoreWrites: true)
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute("on") == SessionResponse(output: stateReport))
        #expect(await device.writes == ["on"])
        #expect(await device.reads == 1)
    }

    @Test func readFailureDoesNotReportSuccessfulState() async {
        let device = SessionFakeDevice(readFailure: .timeout)
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute("on") == SessionResponse(error: "error: device request failed (reachability unconfirmed): timeout\n"))
        #expect(await device.writes == ["on"])
        #expect(await device.reads == 1)
        #expect(await sut.execute("status") == SessionResponse(error: "error: device request failed (reachability unconfirmed): timeout\n"))
    }

    @Test func writeFailureDoesNotReadOrClaimSuccess() async {
        let device = SessionFakeDevice(writeFailure: .timeout)
        var sut = session(device)
        _ = await sut.execute("select 1")
        #expect(await sut.execute("on") == SessionResponse(error: "error: device request failed (reachability unconfirmed): timeout\n"))
        #expect(await device.state == initialState)
        #expect(await device.writes == ["on"])
        #expect(await device.reads == 0)
    }

    @Test func helpQuitWhitespaceAndBlankInputAreSocketFree() async {
        let device = SessionFakeDevice()
        var sut = session(device)
        #expect(DeviceSession.help == commandHelp)
        #expect(await sut.execute(" help \t") == SessionResponse(output: commandHelp))
        #expect(await sut.execute(" \t") == SessionResponse())
        #expect(await sut.execute("quit") == SessionResponse(output: "Bye.\n", shouldQuit: true))
        #expect(await device.state == initialState)
        #expect(await device.writes.isEmpty)
        #expect(await device.reads == 0)
    }
}
