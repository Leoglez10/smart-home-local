import Foundation

/// Devices the user has seen, kept across panel openings and app restarts.
/// Only identity is stored (vendor, address, identifier, model); device state never is,
/// because a remembered state would be stale.
public struct RememberedDevices: Codable, Equatable, Sendable {
    private struct Entry: Codable, Equatable, Sendable {
        var vendor: String
        var address: String
        var identifier: String
        var model: String?

        init(_ device: DiscoveredDevice) {
            vendor = device.vendor.rawValue
            address = device.address
            identifier = device.identifier
            model = device.model
        }

        /// Entries from an unknown vendor (for example a future version) are skipped.
        var device: DiscoveredDevice? {
            Vendor(rawValue: vendor).map {
                DiscoveredDevice(vendor: $0, address: address, identifier: identifier, model: model, state: nil)
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case entries, selectedEntry, names }

    private var entries: [Entry]
    private var selectedEntry: Entry?
    /// User-chosen names keyed by `key(for:)`; stored only on this Mac.
    private var names: [String: String]

    public init(devices: [DiscoveredDevice] = [], selected: DiscoveredDevice? = nil,
                names: [String: String] = [:]) {
        entries = devices.map(Entry.init)
        selectedEntry = selected.map(Entry.init)
        self.names = names
    }

    /// Data saved before names existed has no `names` key; treat it as no names.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([Entry].self, forKey: .entries)
        selectedEntry = try container.decodeIfPresent(Entry.self, forKey: .selectedEntry)
        names = try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(selectedEntry, forKey: .selectedEntry)
        try container.encode(names, forKey: .names)
    }

    public var devices: [DiscoveredDevice] { entries.compactMap(\.device) }
    public var selected: DiscoveredDevice? { selectedEntry?.device }
    public func name(for device: DiscoveredDevice) -> String? { names[Self.key(for: device)] }

    /// Stable identity: vendor plus vendor identifier (MAC for WiZ). Addresses can change.
    public static func key(for device: DiscoveredDevice) -> String {
        "\(device.vendor.rawValue)|\(device.identifier)"
    }
}

/// Persistence seam for the menu bar model. Main-actor bound like the model itself.
@MainActor
public protocol DeviceStore: AnyObject {
    func load() -> RememberedDevices
    func save(_ remembered: RememberedDevices)
}

/// Local JSON in UserDefaults. Unreadable data is treated as "nothing remembered".
@MainActor
public final class UserDefaultsDeviceStore: DeviceStore {
    public static let key = "rememberedDevices"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> RememberedDevices {
        guard let data = defaults.data(forKey: Self.key),
              let remembered = try? JSONDecoder().decode(RememberedDevices.self, from: data) else {
            return RememberedDevices()
        }
        return remembered
    }

    public func save(_ remembered: RememberedDevices) {
        guard let data = try? JSONEncoder().encode(remembered) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
