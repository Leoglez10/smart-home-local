import Foundation

/// A device found on the LAN, before any driver is attached.
public struct DiscoveredDevice: Equatable, Sendable {
    public var vendor: Vendor
    public var address: String
    /// Stable vendor identifier (MAC for WiZ, `did` for CozyLife).
    public var identifier: String
    public var model: String?
    public var state: DeviceState?

    public init(vendor: Vendor, address: String, identifier: String, model: String?, state: DeviceState?) {
        self.vendor = vendor
        self.address = address
        self.identifier = identifier
        self.model = model
        self.state = state
    }
}

/// One per vendor. Must use the vendor's own discovery mechanism (broadcast/mDNS/SSDP),
/// never a subnet sweep.
public protocol DiscoveryProvider: Sendable {
    var vendor: Vendor { get }
    func discover(timeout: TimeInterval) async throws -> [DiscoveredDevice]
}

/// Renders the `shl discover` output.
public enum DiscoveryReport {
    public static func render(_ devices: [DiscoveredDevice], searched: [Vendor]) -> String {
        var out = "Smart Home Discovery\n\n"
        for vendor in searched {
            out += "[\(vendor.displayName)]\n"
            let found = devices.filter { $0.vendor == vendor }
            if found.isEmpty {
                out += "(no devices found)\n\n"
                continue
            }
            for device in found {
                out += "\(device.address)\n"
                out += "Model: \(device.model ?? "unknown")\n"
                out += "State: \(stateLabel(device.state?.isOn))\n\n"
            }
        }
        // Blocks are separated by a blank line; the report ends with exactly one newline.
        if out.hasSuffix("\n\n") { out.removeLast() }
        return out
    }

    private static func stateLabel(_ isOn: Bool?) -> String {
        switch isOn {
        case true?: "ON"
        case false?: "OFF"
        case nil: "unknown"
        }
    }
}
