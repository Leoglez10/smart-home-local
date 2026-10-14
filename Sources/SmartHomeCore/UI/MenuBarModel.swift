import Foundation
import Observation
import OSLog

private let modelLog = Logger(subsystem: "dev.leoglez.smart-home-local", category: "MenuBarModel")

/// A connected device as the UI sees it: the common driver plus verified metadata.
public struct MenuBarConnection: Sendable {
    public let device: any SmartDevice
    /// Verified color-temperature range for this device, when it reported one.
    public let temperatureRange: ClosedRange<Int>?

    public init(device: any SmartDevice, temperatureRange: ClosedRange<Int>? = nil) {
        self.device = device
        self.temperatureRange = temperatureRange
    }
}

/// Observable menu bar model. Construction is inert; every network operation
/// starts from an explicit user action and is serialized by the busy guard.
@MainActor
@Observable
public final class MenuBarModel {
    private enum Reachability {
        static let unconfirmed = "Unconfirmed"
        static let reachable = "Reachable"
        static let unavailable = "Unavailable"
    }

    private let discovery: DiscoveryService
    private let connector: @Sendable (DiscoveredDevice) async throws -> MenuBarConnection
    private var connection: MenuBarConnection?
    private let store: (any DeviceStore)?
    /// Keys of remembered devices that did not answer the most recent discovery.
    private var missingKeys: Set<String> = []
    /// User-chosen names keyed by device identity. Local only; never sent to devices.
    private var names: [String: String] = [:]
    public static let maximumNameLength = 40

    public private(set) var devices: [DiscoveredDevice] = []
    public private(set) var selected: DiscoveredDevice?
    public private(set) var state: DeviceState?
    public private(set) var capabilities: DeviceCapabilities = []
    public private(set) var temperatureRange: ClosedRange<Int>?
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var reachability = Reachability.unconfirmed

    /// Real wiring: default vendors, a WiZ connector, and remembered devices from
    /// UserDefaults. Restoring reads only local storage; no network I/O happens here.
    public convenience init() {
        self.init(store: UserDefaultsDeviceStore())
    }

    /// Real wiring with an explicit store; `nil` keeps nothing between launches.
    public convenience init(store: (any DeviceStore)?) {
        self.init(discovery: .default(), connector: { device in
            let wiz = try await WiZDevice.connect(device)
            return MenuBarConnection(device: wiz, temperatureRange: wiz.temperatureRange)
        }, store: store)
    }

    /// Injectable seams for tests, previews, and the offline demo.
    public init(discovery: DiscoveryService,
                connector: @escaping @Sendable (DiscoveredDevice) async throws -> MenuBarConnection,
                store: (any DeviceStore)? = nil) {
        self.discovery = discovery
        self.connector = connector
        self.store = store
        if let remembered = store?.load() {
            devices = remembered.devices
            selected = remembered.selected
            for device in remembered.devices {
                if let name = remembered.name(for: device) { names[Self.key(device)] = name }
            }
        }
    }

    /// The user's name for a device, or nil when the automatic label applies.
    public func customName(for device: DiscoveredDevice) -> String? {
        names[Self.key(device)]
    }

    /// Saves a local name: trimmed and capped; empty restores the automatic label.
    /// Purely local bookkeeping, so it needs no busy guard and sends nothing.
    public func rename(_ device: DiscoveredDevice, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNameLength))
        names[Self.key(device)] = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    /// True when a listed device was remembered but did not answer the latest discovery.
    public func wasMissingInLastDiscovery(_ device: DiscoveredDevice) -> Bool {
        missingKeys.contains(Self.key(device))
    }

    /// Runs every provider and merges results into the remembered list: found devices
    /// are updated or added; devices that did not answer stay listed as missing,
    /// because UDP discovery can miss a light that is still there.
    public func discover() async {
        guard beginOperation() else { return }
        defer { endOperation() }
        let outcome = await discovery.discover(timeout: 4)
        modelLog.info("discover: \(outcome.devices.count) devices, failures: \(String(describing: outcome.failures), privacy: .public)")
        var merged = devices
        for found in outcome.devices {
            if let index = merged.firstIndex(where: { Self.key($0) == Self.key(found) }) {
                merged[index] = found
            } else {
                merged.append(found)
            }
        }
        devices = merged
        let foundKeys = Set(outcome.devices.map(Self.key))
        missingKeys = Set(merged.map(Self.key)).subtracting(foundKeys)
        if let current = selected,
           let refreshed = outcome.devices.first(where: { Self.key($0) == Self.key(current) }) {
            selected = refreshed
            if refreshed.address != current.address {
                // The driver talks to the old address; a reconnect is required.
                clearConnectionState()
            }
        }
        persist()
        if outcome.failures.isEmpty {
            errorMessage = nil
        } else {
            let sorted = outcome.failures.sorted { $0.key.rawValue < $1.key.rawValue }
            errorMessage = sorted.map { "\($0.key.displayName): \($0.value)" }.joined(separator: "\n")
        }
    }

    /// Connects only WiZ. CozyLife stays discover-only and never reaches the connector.
    public func select(_ device: DiscoveredDevice) async {
        guard beginOperation() else { return }
        defer { endOperation() }
        selected = device
        errorMessage = nil
        clearConnectionState()
        persist()
        modelLog.info("select: \(device.vendor.displayName) at \(device.address)")
        guard device.vendor == .wiz else {
            errorMessage = "\(device.vendor.displayName) is discover-only; control is not verified."
            return
        }
        do {
            let newConnection = try await connector(device)
            connection = newConnection
            capabilities = newConnection.device.capabilities
            temperatureRange = newConnection.temperatureRange
        } catch {
            connection = nil
            errorMessage = String(describing: error)
            reachability = Reachability.unavailable
            modelLog.error("connect failed: \(String(describing: error), privacy: .public)")
            return
        }
        // A failed read keeps the connection: the next refresh retries on it.
        try? await readState()
    }

    /// Connects and reads a remembered or moved WiZ selection that has no live
    /// connection yet (for example when the panel opens). Read-only; never writes.
    public func reconnectIfNeeded() async {
        guard !isBusy, connection == nil, let current = selected, current.vendor == .wiz else { return }
        await select(current)
    }

    /// Removes a device from the remembered list; forgetting the selection disconnects it.
    public func forget(_ device: DiscoveredDevice) async {
        guard beginOperation() else { return }
        defer { endOperation() }
        devices.removeAll { Self.key($0) == Self.key(device) }
        missingKeys.remove(Self.key(device))
        names[Self.key(device)] = nil
        if let current = selected, Self.key(current) == Self.key(device) {
            clearSelection()
        }
        persist()
    }

    /// Re-reads real state for the selected WiZ device.
    public func refresh() async {
        guard beginOperation() else { return }
        defer { endOperation() }
        guard connection != nil else {
            errorMessage = "No selected device to refresh."
            return
        }
        state = nil
        reachability = Reachability.unconfirmed
        try? await readState()
    }

    public func setPower(_ on: Bool) async {
        guard beginOperation() else { return }
        defer { endOperation() }
        guard let current = connection else {
            errorMessage = "No selected device."
            return
        }
        guard current.device.capabilities.contains(.power) else {
            errorMessage = "Power is not supported by this device."
            return
        }
        await performWrite {
            if on { try await current.device.turnOn() } else { try await current.device.turnOff() }
        }
    }

    public func setBrightness(_ value: Int) async {
        guard beginOperation() else { return }
        defer { endOperation() }
        guard let current = connection else {
            errorMessage = "No selected device."
            return
        }
        guard current.device.capabilities.contains(.brightness) else {
            errorMessage = "Brightness is not supported by this device."
            return
        }
        guard (0...100).contains(value) else {
            errorMessage = "Brightness must be 0...100."
            return
        }
        await performWrite { try await current.device.setBrightness(value) }
    }

    public func setColor(_ value: RGBColor) async {
        guard beginOperation() else { return }
        defer { endOperation() }
        guard let current = connection else {
            errorMessage = "No selected device."
            return
        }
        guard current.device.capabilities.contains(.color) else {
            errorMessage = "RGB color is not supported by this device."
            return
        }
        guard [value.red, value.green, value.blue].allSatisfy({ (0...255).contains($0) }) else {
            errorMessage = "Each RGB channel must be 0...255."
            return
        }
        await performWrite { try await current.device.setColor(value) }
    }

    public func setTemperature(_ kelvin: Int) async {
        guard beginOperation() else { return }
        defer { endOperation() }
        guard let current = connection else {
            errorMessage = "No selected device."
            return
        }
        guard current.device.capabilities.contains(.colorTemperature) else {
            errorMessage = "Color temperature is not supported by this device."
            return
        }
        guard let range = current.temperatureRange, range.contains(kelvin) else {
            errorMessage = "Temperature \(kelvin) K is outside the verified range or no range is verified."
            return
        }
        await performWrite { try await current.device.setColorTemperature(kelvin) }
    }

    // MARK: - Private helpers

    /// State goes unknown while a write is in flight; the readback repopulates it.
    private func performWrite(_ write: () async throws -> Void) async {
        state = nil
        reachability = Reachability.unconfirmed
        do {
            try await write()
        } catch {
            state = nil
            reachability = Reachability.unavailable
            errorMessage = String(describing: error)
            return
        }
        try? await readState()
    }

    /// A successful read is the only proof of reachability and current state.
    private func readState() async throws {
        guard let connection else { throw SmartDeviceError.unsupported("No connection") }
        do {
            state = try await connection.device.getState()
            reachability = Reachability.reachable
            errorMessage = nil
        } catch {
            state = nil
            reachability = Reachability.unavailable
            errorMessage = String(describing: error)
            throw error
        }
    }

    private func beginOperation() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    private func endOperation() {
        isBusy = false
    }

    private func clearConnectionState() {
        connection = nil
        state = nil
        capabilities = []
        temperatureRange = nil
        reachability = Reachability.unconfirmed
    }

    private func clearSelection() {
        selected = nil
        clearConnectionState()
    }

    private func persist() {
        store?.save(RememberedDevices(devices: devices, selected: selected, names: names))
    }

    private static func key(_ device: DiscoveredDevice) -> String {
        RememberedDevices.key(for: device)
    }
}
