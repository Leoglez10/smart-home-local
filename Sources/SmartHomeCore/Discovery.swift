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

public struct DiscoveryOutcome: Sendable {
    public var devices: [DiscoveredDevice]
    /// Vendor -> error description. A failing vendor never hides the others' results.
    public var failures: [Vendor: String]
}

/// Runs every provider concurrently and aggregates results in provider order.
public struct DiscoveryService: Sendable {
    public let providers: [any DiscoveryProvider]

    public init(providers: [any DiscoveryProvider]) {
        self.providers = providers
    }

    public static func `default`() -> DiscoveryService {
        DiscoveryService(providers: [WiZDiscoveryProvider(), CozyLifeDiscoveryProvider()])
    }

    public var vendors: [Vendor] { providers.map(\.vendor) }

    public func discover(timeout: TimeInterval) async -> DiscoveryOutcome {
        let results = await withTaskGroup(of: (Int, Vendor, Result<[DiscoveredDevice], Error>).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do { return (index, provider.vendor, .success(try await provider.discover(timeout: timeout))) }
                    catch { return (index, provider.vendor, .failure(error)) }
                }
            }
            var collected: [(Int, Vendor, Result<[DiscoveredDevice], Error>)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }
        }
        var outcome = DiscoveryOutcome(devices: [], failures: [:])
        for (_, vendor, result) in results {
            switch result {
            case .success(let devices): outcome.devices += devices
            case .failure(let error): outcome.failures[vendor] = String(describing: error)
            }
        }
        return outcome
    }
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
