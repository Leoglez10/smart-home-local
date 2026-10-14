import Foundation
import Testing
import SmartHomeCore

private let menuFixture = DiscoveredDevice(
    vendor: .wiz, address: "192.0.2.7", identifier: "menu-fixture",
    model: "Fixture light", state: DeviceState(isOn: true, brightness: 99))
private let menuSnapshot = DeviceState(isOn: false, brightness: 42, colorTemperature: 3000)

/// Synchronizes test tasks without sleeps, sockets, or polling.
private actor MenuGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    func waitForEntry() async {
        if !entered {
            await withCheckedContinuation { entryWaiters.append($0) }
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor MenuProvider: DiscoveryProvider {
    nonisolated let vendor: Vendor
    private var result: Result<[DiscoveredDevice], SmartDeviceError>
    private let gate: MenuGate?
    private(set) var calls = 0

    init(_ vendor: Vendor = .wiz, devices: [DiscoveredDevice] = [menuFixture],
         failure: SmartDeviceError? = nil, gate: MenuGate? = nil) {
        self.vendor = vendor
        result = failure.map { .failure($0) } ?? .success(devices)
        self.gate = gate
    }

    func discover(timeout: TimeInterval) async throws -> [DiscoveredDevice] {
        calls += 1
        if let gate { await gate.pause() }
        return try result.get()
    }

    func replace(devices: [DiscoveredDevice]) { result = .success(devices) }
}

private actor MenuDevice: SmartDevice {
    nonisolated let id = "menu-fixture"
    nonisolated let vendor = Vendor.wiz
    nonisolated let address = "192.0.2.7"
    nonisolated let name = "Fixture light"
    nonisolated let capabilities: DeviceCapabilities
    private var snapshot = menuSnapshot
    private var readFailure: SmartDeviceError?
    private var writeFailure: SmartDeviceError?
    private var readGate: MenuGate?
    private var writeGate: MenuGate?
    private(set) var events: [String] = []

    init(capabilities: DeviceCapabilities = [.power, .brightness, .color, .colorTemperature]) {
        self.capabilities = capabilities
    }

    func configure(snapshot: DeviceState = menuSnapshot, readFailure: SmartDeviceError? = nil,
                   writeFailure: SmartDeviceError? = nil, readGate: MenuGate? = nil,
                   writeGate: MenuGate? = nil) {
        self.snapshot = snapshot
        self.readFailure = readFailure
        self.writeFailure = writeFailure
        self.readGate = readGate
        self.writeGate = writeGate
    }

    func getState() async throws -> DeviceState {
        events.append("read")
        if let readGate { await readGate.pause() }
        if let readFailure { throw readFailure }
        return snapshot
    }

    private func write(_ event: String) async throws {
        events.append(event)
        if let writeGate { await writeGate.pause() }
        if let writeFailure { throw writeFailure }
        // ACK does not imply a changed snapshot. Tests choose the readback explicitly.
    }

    func turnOn() async throws { try await write("on") }
    func turnOff() async throws { try await write("off") }
    func setBrightness(_ percent: Int) async throws { try await write("brightness \(percent)") }
    func setColor(_ color: RGBColor) async throws {
        try await write("color \(color.red) \(color.green) \(color.blue)")
    }
    func setColorTemperature(_ kelvin: Int) async throws { try await write("temperature \(kelvin)") }
}

private actor MenuConnector {
    private let device: MenuDevice
    private let range: ClosedRange<Int>?
    private let failure: SmartDeviceError?
    private let gate: MenuGate?
    private(set) var requests: [DiscoveredDevice] = []

    init(device: MenuDevice, range: ClosedRange<Int>? = 2200...6500,
         failure: SmartDeviceError? = nil, gate: MenuGate? = nil) {
        self.device = device
        self.range = range
        self.failure = failure
        self.gate = gate
    }

    func connect(_ discovered: DiscoveredDevice) async throws -> MenuBarConnection {
        requests.append(discovered)
        if let gate { await gate.pause() }
        if let failure { throw failure }
        return MenuBarConnection(device: device, temperatureRange: range)
    }
}

@MainActor
private final class MemoryStore: DeviceStore {
    var remembered: RememberedDevices
    private(set) var saves = 0

    init(_ remembered: RememberedDevices = RememberedDevices()) { self.remembered = remembered }
    func load() -> RememberedDevices { remembered }
    func save(_ remembered: RememberedDevices) {
        self.remembered = remembered
        saves += 1
    }
}

@MainActor
private func menuModel(provider: MenuProvider = MenuProvider(), connector: MenuConnector,
                       store: (any DeviceStore)? = nil) -> MenuBarModel {
    MenuBarModel(discovery: DiscoveryService(providers: [provider]), connector: { device in
        try await connector.connect(device)
    }, store: store)
}

private var statelessFixture: DiscoveredDevice {
    var device = menuFixture
    device.state = nil
    return device
}

@MainActor
@Suite struct MenuBarModelTests {
    @Test func initializationDoesNotDiscoverConnectReadOrWrite() async {
        let provider = MenuProvider()
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: provider, connector: connector)

        #expect(model.devices.isEmpty)
        #expect(model.selected == nil)
        #expect(model.state == nil)
        #expect(model.capabilities.isEmpty)
        #expect(model.temperatureRange == nil)
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
        #expect(model.reachability == "Unconfirmed")
        #expect(await provider.calls == 0)
        #expect(await connector.requests.isEmpty)
        #expect(await device.events.isEmpty)

        let defaultModel = MenuBarModel()
        #expect(defaultModel.devices.isEmpty)
        #expect(defaultModel.state == nil)
        #expect(!defaultModel.isBusy)
    }

    @Test func discoveryIsExplicitAndDoesNotConnectOrTrustAdvertisedState() async {
        let cozy = DiscoveredDevice(vendor: .cozyLife, address: "192.0.2.8", identifier: "cozy",
                                    model: nil, state: nil)
        let provider = MenuProvider(devices: [menuFixture, cozy])
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: provider, connector: connector)

        await model.discover()

        #expect(model.devices == [menuFixture, cozy])
        #expect(model.selected == nil)
        #expect(model.state == nil)
        #expect(model.reachability == "Unconfirmed")
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
        #expect(await provider.calls == 1)
        #expect(await connector.requests.isEmpty)
        #expect(await device.events.isEmpty)
    }

    @Test(arguments: [Vendor.wiz, Vendor.cozyLife])
    func discoverySurfacesEachVendorFailureWithOtherVendorSuccess(failing: Vendor) async {
        let successful: Vendor = failing == .wiz ? .cozyLife : .wiz
        var found = menuFixture
        found.vendor = successful
        let connector = MenuConnector(device: MenuDevice())
        let model = MenuBarModel(discovery: DiscoveryService(providers: [
            MenuProvider(failing, failure: .transport("fixture discovery failure")),
            MenuProvider(successful, devices: [found]),
        ]), connector: { try await connector.connect($0) })

        await model.discover()

        #expect(model.devices == [found])
        #expect(model.errorMessage?.contains(failing.displayName) == true)
        #expect(model.errorMessage?.contains("fixture discovery failure") == true)
        #expect(!model.isBusy)
        #expect(await connector.requests.isEmpty)
    }

    @Test func allVendorFailuresAreVisibleAndUnseenDevicesStayListedAsMissing() async {
        let provider = MenuProvider()
        let connector = MenuConnector(device: MenuDevice())
        let model = MenuBarModel(discovery: DiscoveryService(providers: [
            provider, MenuProvider(.cozyLife, failure: .timeout),
        ]), connector: { try await connector.connect($0) })
        await model.discover()
        #expect(model.devices == [menuFixture])
        #expect(!model.wasMissingInLastDiscovery(menuFixture))
        await provider.replace(devices: [])
        await model.discover()
        #expect(model.devices == [menuFixture])
        #expect(model.wasMissingInLastDiscovery(menuFixture))
        #expect(model.errorMessage?.contains("CozyLife") == true)
        await provider.replace(devices: [menuFixture])
        await model.discover()
        #expect(!model.wasMissingInLastDiscovery(menuFixture))

        let failures = MenuBarModel(discovery: DiscoveryService(providers: [
            MenuProvider(.wiz, failure: .timeout),
            MenuProvider(.cozyLife, failure: .transport("unavailable")),
        ]), connector: { try await connector.connect($0) })
        await failures.discover()
        #expect(failures.devices.isEmpty)
        #expect(failures.errorMessage?.contains("WiZ") == true)
        #expect(failures.errorMessage?.contains("CozyLife") == true)
    }

    @Test func selectionReadsDriverStateAndRefreshKeepsUnknownFieldsUnknown() async {
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(connector: connector)
        await model.select(menuFixture)

        #expect(model.selected == menuFixture)
        #expect(model.state == menuSnapshot)
        #expect(model.capabilities == device.capabilities)
        #expect(model.temperatureRange == 2200...6500)
        #expect(model.reachability == "Reachable")
        #expect(model.errorMessage == nil)
        #expect(await connector.requests == [menuFixture])
        #expect(await device.events == ["read"])

        await device.configure(snapshot: DeviceState(brightness: 25))
        await model.refresh()
        #expect(model.state == DeviceState(brightness: 25))
        #expect(model.state?.isOn == nil)
        #expect(model.state?.color == nil)
        #expect(model.state?.colorTemperature == nil)
        await device.configure(snapshot: DeviceState())
        await model.refresh()
        #expect(model.state == DeviceState())
        #expect(model.state?.isOn == nil)
        #expect(model.reachability == "Reachable") // A reply, not proof that power is ON.
        #expect(await connector.requests.count == 1)
        #expect(await device.events == ["read", "read", "read"])
    }

    @Test func newSelectionClearsPriorStateBeforeAwaitingConnection() async {
        let device = MenuDevice()
        let gate = MenuGate()
        let firstConnector = MenuConnector(device: device)
        let model = menuModel(connector: firstConnector)
        await model.select(menuFixture)
        var second = menuFixture
        second.identifier = "second"
        second.address = "192.0.2.9"
        await device.configure(readGate: gate)

        let task = Task { await model.select(second) }
        await gate.waitForEntry()
        #expect(model.selected == second)
        #expect(model.state == nil)
        #expect(model.reachability == "Unconfirmed")
        #expect(model.isBusy)
        await gate.release()
        await task.value
        #expect(model.state == menuSnapshot)
        #expect(!model.isBusy)
    }

    @Test(arguments: ["removed", "identifier", "vendor"])
    func discoveryKeepsSelectionAndConnectionWhenTheSelectedDeviceIsNotSeen(change: String) async {
        let provider = MenuProvider()
        let device = MenuDevice()
        let model = menuModel(provider: provider, connector: MenuConnector(device: device))
        await model.discover()
        await model.select(menuFixture)
        var other = menuFixture
        if change == "identifier" { other.identifier = "replacement" }
        if change == "vendor" { other.vendor = .cozyLife }
        await provider.replace(devices: change == "removed" ? [] : [other])
        await model.discover()

        #expect(model.devices == (change == "removed" ? [menuFixture] : [menuFixture, other]))
        #expect(model.wasMissingInLastDiscovery(menuFixture))
        #expect(model.selected == menuFixture)
        #expect(model.state == menuSnapshot)
        #expect(model.reachability == "Reachable")
        await model.setPower(true)
        #expect(await device.events == ["read", "on", "read"])
    }

    @Test func discoveryUpdatesAMovedSelectionAndRequiresReconnectBeforeControl() async {
        let provider = MenuProvider()
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: provider, connector: connector)
        await model.discover()
        await model.select(menuFixture)
        var moved = menuFixture
        moved.address = "192.0.2.9"
        await provider.replace(devices: [moved])
        await model.discover()

        #expect(model.devices == [moved])
        #expect(model.selected == moved)
        #expect(model.state == nil)
        #expect(model.capabilities.isEmpty)
        #expect(model.temperatureRange == nil)
        #expect(model.reachability == "Unconfirmed")
        await model.setPower(true)
        #expect(model.errorMessage != nil)
        #expect(await device.events == ["read"])
        await model.reconnectIfNeeded()
        #expect(await connector.requests == [menuFixture, moved])
        #expect(model.state == menuSnapshot)
    }

    @Test func rediscoveryRetainsSameEndpointWithoutReplacingDriverState() async {
        let provider = MenuProvider()
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: provider, connector: connector)
        await model.select(menuFixture)
        var updated = menuFixture
        updated.model = "Updated discovery label"
        updated.state = DeviceState(isOn: true, brightness: 100)
        await provider.replace(devices: [updated])
        await model.discover()
        #expect(model.selected == updated)
        #expect(model.state == menuSnapshot)
        #expect(model.reachability == "Reachable")
        await model.setPower(true)
        #expect(await connector.requests.count == 1)
        #expect(await device.events == ["read", "on", "read"])
    }

    @Test func failedDiscoveryKeepsSelectionAndConnection() async {
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: MenuProvider(failure: .timeout), connector: connector)
        await model.select(menuFixture)
        await model.discover()
        #expect(model.selected == menuFixture)
        #expect(model.state == menuSnapshot)
        #expect(model.reachability == "Reachable")
        #expect(model.errorMessage?.contains("WiZ") == true)
        await model.refresh()
        #expect(await device.events == ["read", "read"])
    }

    @Test func restoresRememberedDevicesAndSelectionWithoutIO() async {
        let cozy = DiscoveredDevice(vendor: .cozyLife, address: "192.0.2.8", identifier: "cozy",
                                    model: "qwialM", state: nil)
        let store = MemoryStore(RememberedDevices(devices: [statelessFixture, cozy], selected: statelessFixture))
        let provider = MenuProvider()
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: provider, connector: connector, store: store)

        #expect(model.devices == [statelessFixture, cozy])
        #expect(model.selected == statelessFixture)
        #expect(model.state == nil)
        #expect(model.reachability == "Unconfirmed")
        #expect(!model.wasMissingInLastDiscovery(statelessFixture))
        #expect(await provider.calls == 0)
        #expect(await connector.requests.isEmpty)
        #expect(await device.events.isEmpty)
        #expect(store.saves == 0)
    }

    @Test func discoverySelectionAndForgetArePersistedWithoutDeviceState() async {
        let store = MemoryStore()
        let device = MenuDevice()
        let model = menuModel(connector: MenuConnector(device: device), store: store)
        await model.discover()
        await model.select(menuFixture)
        #expect(store.remembered.devices == [statelessFixture])
        #expect(store.remembered.selected == statelessFixture)

        let restored = menuModel(connector: MenuConnector(device: device), store: store)
        #expect(restored.devices == [statelessFixture])
        #expect(restored.selected == statelessFixture)
        await restored.forget(statelessFixture)
        #expect(restored.devices.isEmpty)
        #expect(restored.selected == nil)
        #expect(restored.state == nil)
        #expect(store.remembered == RememberedDevices())
    }

    @Test func forgettingAnUnselectedDeviceKeepsTheSelectedConnection() async {
        var other = menuFixture
        other.identifier = "other"
        let device = MenuDevice()
        let model = menuModel(provider: MenuProvider(devices: [menuFixture, other]),
                              connector: MenuConnector(device: device), store: MemoryStore())
        await model.discover()
        await model.select(menuFixture)
        await model.forget(other)
        #expect(model.devices == [menuFixture])
        #expect(model.selected == menuFixture)
        #expect(model.state == menuSnapshot)
        #expect(model.reachability == "Reachable")
    }

    @Test func reconnectIfNeededReadsOnlyAnUnconnectedRememberedWiZ() async {
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(connector: connector,
                              store: MemoryStore(RememberedDevices(devices: [statelessFixture],
                                                                   selected: statelessFixture)))
        await model.reconnectIfNeeded()
        #expect(await connector.requests == [statelessFixture])
        #expect(model.state == menuSnapshot)
        #expect(model.reachability == "Reachable")
        await model.reconnectIfNeeded()
        #expect(await connector.requests.count == 1)
        #expect(await device.events == ["read"])

        let cozy = DiscoveredDevice(vendor: .cozyLife, address: "192.0.2.8", identifier: "cozy",
                                    model: nil, state: nil)
        let otherConnector = MenuConnector(device: device)
        let cozyModel = menuModel(connector: otherConnector,
                                  store: MemoryStore(RememberedDevices(devices: [cozy], selected: cozy)))
        await cozyModel.reconnectIfNeeded()
        let empty = menuModel(connector: otherConnector, store: MemoryStore())
        await empty.reconnectIfNeeded()
        #expect(await otherConnector.requests.isEmpty)
        #expect(await device.events == ["read"])
    }

    @Test func renamingIsLocalPersistedAndSurvivesRediscoveryAndAddressChanges() async {
        let store = MemoryStore()
        let provider = MenuProvider()
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(provider: provider, connector: connector, store: store)
        await model.discover()
        #expect(model.customName(for: menuFixture) == nil)
        model.rename(menuFixture, to: "Living room")
        #expect(model.customName(for: menuFixture) == "Living room")
        #expect(model.errorMessage == nil)
        #expect(await connector.requests.isEmpty)
        #expect(await device.events.isEmpty)

        var moved = menuFixture
        moved.address = "192.0.2.9"
        moved.model = "Renamed by discovery"
        await provider.replace(devices: [moved])
        await model.discover()
        #expect(model.customName(for: moved) == "Living room")

        let restored = menuModel(connector: connector, store: store)
        #expect(restored.customName(for: statelessFixture) == "Living room")
        #expect(store.remembered.name(for: menuFixture) == "Living room")
    }

    @Test func renameTrimsCapsLengthAndEmptyRestoresAutomaticName() {
        let store = MemoryStore()
        let cozy = DiscoveredDevice(vendor: .cozyLife, address: "192.0.2.8", identifier: "cozy",
                                    model: nil, state: nil)
        let model = menuModel(connector: MenuConnector(device: MenuDevice()), store: store)
        model.rename(cozy, to: "  Kitchen plug \n")
        #expect(model.customName(for: cozy) == "Kitchen plug")
        model.rename(cozy, to: String(repeating: "x", count: 80))
        #expect(model.customName(for: cozy) == String(repeating: "x", count: 40))
        model.rename(cozy, to: "   ")
        #expect(model.customName(for: cozy) == nil)
        #expect(store.remembered.name(for: cozy) == nil)
        #expect(store.saves == 3)
    }

    @Test func forgettingADeviceAlsoForgetsItsName() async {
        let store = MemoryStore()
        let model = menuModel(connector: MenuConnector(device: MenuDevice()), store: store)
        await model.discover()
        model.rename(menuFixture, to: "Desk")
        await model.forget(menuFixture)
        #expect(model.customName(for: menuFixture) == nil)
        #expect(store.remembered == RememberedDevices())
    }

    @Test func decodesStoredDataSavedBeforeNamesExisted() throws {
        let suite = "smart-home-local-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = """
        {"entries":[{"vendor":"WiZ","address":"192.0.2.7","identifier":"menu-fixture","model":"Fixture light"}],
         "selectedEntry":{"vendor":"WiZ","address":"192.0.2.7","identifier":"menu-fixture","model":"Fixture light"}}
        """
        defaults.set(Data(legacy.utf8), forKey: UserDefaultsDeviceStore.key)
        let loaded = UserDefaultsDeviceStore(defaults: defaults).load()
        #expect(loaded.devices == [statelessFixture])
        #expect(loaded.selected == statelessFixture)
        #expect(loaded.name(for: statelessFixture) == nil)
    }

    @Test func userDefaultsStoreRoundTripsAndIgnoresCorruptData() throws {
        let suite = "smart-home-local-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsDeviceStore(defaults: defaults)
        #expect(store.load() == RememberedDevices())
        let value = RememberedDevices(devices: [menuFixture], selected: menuFixture)
        store.save(value)
        #expect(UserDefaultsDeviceStore(defaults: defaults).load() == value)
        #expect(value.devices == [statelessFixture])
        defaults.set(Data("not json".utf8), forKey: UserDefaultsDeviceStore.key)
        #expect(store.load() == RememberedDevices())
    }

    @Test(arguments: MenuAction.allCases)
    fileprivate func everySetterUsesReadbackRatherThanRequestedValue(action: MenuAction) async {
        let device = MenuDevice()
        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        let readback = DeviceState(isOn: action != .on, brightness: 17,
                                  color: RGBColor(red: 2, green: 3, blue: 4), colorTemperature: 4200)
        await device.configure(snapshot: readback)

        await action.apply(to: model)

        #expect(await device.events == ["read", action.event, "read"])
        #expect(model.state == readback)
        #expect(model.reachability == "Reachable")
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
    }

    @Test func noSelectionRejectsRefreshAndAllSettersWithoutIO() async {
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(connector: connector)
        await model.refresh()
        #expect(model.errorMessage != nil)
        for action in MenuAction.allCases {
            await action.apply(to: model)
            #expect(model.errorMessage != nil)
            #expect(!model.isBusy)
        }
        #expect(model.state == nil)
        #expect(model.reachability == "Unconfirmed")
        #expect(await connector.requests.isEmpty)
        #expect(await device.events.isEmpty)
    }

    @Test(arguments: MenuAction.allCases)
    fileprivate func missingCapabilityRejectsEverySetterBeforeAnyWrite(action: MenuAction) async {
        let device = MenuDevice(capabilities: [])
        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        await action.apply(to: model)
        #expect(model.errorMessage != nil)
        #expect(model.state == menuSnapshot)
        #expect(await device.events == ["read"])
        #expect(!model.isBusy)
    }

    @Test func rejectsBrightnessAndEveryRGBChannelOutsideBoundsBeforeWriting() async {
        let device = MenuDevice()
        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        for value in [Int.min, -1, 101, Int.max] {
            await model.setBrightness(value)
            #expect(model.errorMessage != nil)
        }
        for value in [Int.min, -1, 256, Int.max] {
            for color in [RGBColor(red: value, green: 0, blue: 0),
                          RGBColor(red: 0, green: value, blue: 0),
                          RGBColor(red: 0, green: 0, blue: value)] {
                await model.setColor(color)
                #expect(model.errorMessage != nil)
            }
        }
        #expect(await device.events == ["read"])
        #expect(model.state == menuSnapshot)
        #expect(!model.isBusy)
    }

    @Test func temperatureRequiresVerifiedRangeAndRejectsValuesOutsideIt() async {
        let device = MenuDevice()
        let withoutRange = menuModel(connector: MenuConnector(device: device, range: nil))
        await withoutRange.select(menuFixture)
        await withoutRange.setTemperature(3000)
        #expect(withoutRange.errorMessage != nil)
        #expect(await device.events == ["read"])

        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        for kelvin in [Int.min, -1, 0, 2199, 6501, Int.max] {
            await model.setTemperature(kelvin)
            #expect(model.errorMessage != nil)
        }
        #expect(await device.events == ["read", "read"])
        #expect(model.state == menuSnapshot)
    }

    @Test func inclusiveInputBoundariesAreAcceptedAndReadBack() async {
        let device = MenuDevice()
        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        await model.setBrightness(0)
        await model.setBrightness(100)
        await model.setColor(RGBColor(red: 0, green: 255, blue: 0))
        await model.setColor(RGBColor(red: 255, green: 0, blue: 255))
        await model.setTemperature(2200)
        await model.setTemperature(6500)
        #expect(await device.events == ["read", "brightness 0", "read", "brightness 100", "read",
                                       "color 0 255 0", "read", "color 255 0 255", "read",
                                       "temperature 2200", "read", "temperature 6500", "read"])
        #expect(model.errorMessage == nil)
        #expect(model.state == menuSnapshot)
    }

    @Test func cozyLifeNeverConnectsOrControlsAndClearsPreviousWiZState() async {
        let device = MenuDevice()
        let connector = MenuConnector(device: device)
        let model = menuModel(connector: connector)
        await model.select(menuFixture)
        var cozy = menuFixture
        cozy.vendor = .cozyLife
        await model.select(cozy)
        #expect(model.selected == cozy)
        #expect(model.state == nil)
        #expect(model.capabilities.isEmpty)
        #expect(model.temperatureRange == nil)
        #expect(model.reachability == "Unconfirmed")
        #expect(model.errorMessage?.contains("CozyLife") == true)
        await model.refresh()
        for action in MenuAction.allCases { await action.apply(to: model) }
        #expect(model.errorMessage != nil)
        #expect(await connector.requests == [menuFixture])
        #expect(await device.events == ["read"])
        #expect(!model.isBusy)
    }

    @Test func failedConnectionLeavesNoOldStateOrDriver() async {
        let device = MenuDevice()
        let connector = MenuConnector(device: device, failure: .transport("fixture connection failure"))
        let model = menuModel(connector: connector)
        await model.select(menuFixture)
        #expect(model.selected == menuFixture)
        #expect(model.state == nil)
        #expect(model.capabilities.isEmpty)
        #expect(model.temperatureRange == nil)
        #expect(model.reachability == "Unavailable")
        #expect(model.errorMessage?.contains("fixture connection failure") == true)
        await model.setPower(true)
        #expect(await device.events.isEmpty)
        #expect(!model.isBusy)
    }

    @Test(arguments: ["select", "refresh"])
    func failedReadClearsStateAndSuccessfulRetryClearsError(operation: String) async {
        let device = MenuDevice()
        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        await device.configure(readFailure: .timeout)
        if operation == "select" { await model.select(menuFixture) }
        else { await model.refresh() }
        #expect(model.state == nil)
        #expect(model.reachability == "Unavailable")
        #expect(model.errorMessage?.contains("timeout") == true)
        #expect(!model.isBusy)
        await device.configure(snapshot: DeviceState(isOn: true))
        await model.refresh()
        #expect(model.state == DeviceState(isOn: true))
        #expect(model.reachability == "Reachable")
        #expect(model.errorMessage == nil)
    }

    @Test(arguments: MenuAction.allCases, [false, true])
    fileprivate func failedControlOrReadbackNeverReportsSuccess(action: MenuAction, readbackFails: Bool) async {
        let device = MenuDevice()
        let model = menuModel(connector: MenuConnector(device: device))
        await model.select(menuFixture)
        await device.configure(readFailure: readbackFails ? .timeout : nil,
                               writeFailure: readbackFails ? nil : .transport("fixture control failure"))
        await action.apply(to: model)
        #expect(await device.events == (readbackFails ? ["read", action.event, "read"] : ["read", action.event]))
        #expect(model.state == nil)
        #expect(model.reachability == "Unavailable")
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
    }

    @Test(arguments: ["connect", "read", "write", "readback", "discover", "refresh"])
    func busyGuardSerializesEntireOperationsAndRejectsAllReentry(phase: String) async {
        let gate = MenuGate()
        let device = MenuDevice()
        let provider = MenuProvider(gate: phase == "discover" ? gate : nil)
        let connector = MenuConnector(device: device, gate: phase == "connect" ? gate : nil)
        let model = menuModel(provider: provider, connector: connector)
        if phase != "connect" && phase != "read" { await model.select(menuFixture) }
        if phase == "read" || phase == "readback" || phase == "refresh" {
            await device.configure(readGate: gate)
        } else if phase == "write" {
            await device.configure(writeGate: gate)
        }
        let task = Task {
            switch phase {
            case "connect", "read": await model.select(menuFixture)
            case "discover": await model.discover()
            case "refresh": await model.refresh()
            default: await model.setPower(true)
            }
        }
        await gate.waitForEntry()
        #expect(model.isBusy)
        if phase != "discover" {
            #expect(model.state == nil)
            #expect(model.reachability == "Unconfirmed")
        }
        let selected = model.selected
        let events = await device.events
        let requests = await connector.requests
        let discoveryCalls = await provider.calls
        var other = menuFixture
        other.identifier = "must not connect"
        await model.select(other)
        await model.discover()
        await model.refresh()
        for action in MenuAction.allCases { await action.apply(to: model) }
        #expect(model.isBusy)
        #expect(model.selected == selected)
        #expect(await device.events == events)
        #expect(await connector.requests == requests)
        #expect(await provider.calls == discoveryCalls)
        #expect(model.errorMessage == nil)
        await gate.release()
        await task.value
        #expect(!model.isBusy)
        #expect(model.state == menuSnapshot)
        #expect(model.reachability == "Reachable")
    }
}

fileprivate enum MenuAction: String, CaseIterable, Sendable {
    case on, off, brightness, color, temperature

    var event: String {
        switch self {
        case .on: "on"
        case .off: "off"
        case .brightness: "brightness 50"
        case .color: "color 255 0 0"
        case .temperature: "temperature 2700"
        }
    }

    @MainActor
    func apply(to model: MenuBarModel) async {
        switch self {
        case .on: await model.setPower(true)
        case .off: await model.setPower(false)
        case .brightness: await model.setBrightness(50)
        case .color: await model.setColor(RGBColor(red: 255, green: 0, blue: 0))
        case .temperature: await model.setTemperature(2700)
        }
    }
}
