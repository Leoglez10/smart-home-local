import Foundation

/// WiZ discovery: broadcast the pywizlight `registration` probe on UDP 38899, then
/// enrich each bulb with read-only `getSystemConfig` and `getPilot`. Never sends `setPilot`.
public struct WiZDiscoveryProvider: DiscoveryProvider {
    public let vendor: Vendor = .wiz
    private let transport: any UDPTransport

    public init(transport: any UDPTransport = BSDUDPTransport()) {
        self.transport = transport
    }

    public func discover(timeout: TimeInterval) async throws -> [DiscoveredDevice] {
        let replies = try await transport.broadcast(
            WiZCodec.discoveryProbe(), port: WiZCodec.port, sends: 3, interval: 1, listen: timeout)

        var bulbs: [(address: String, mac: String)] = []
        for reply in replies where !bulbs.contains(where: { $0.address == reply.sender }) {
            if let mac = WiZCodec.parseDiscoveryReply(reply.payload) {
                bulbs.append((reply.sender, mac))
            }
        }

        return await withTaskGroup(of: (Int, DiscoveredDevice).self) { group in
            for (index, bulb) in bulbs.enumerated() {
                group.addTask {
                    let config = try? await transport.request(WiZCodec.getSystemConfig(), host: bulb.address, port: WiZCodec.port, timeout: 1.5)
                    let pilot = try? await transport.request(WiZCodec.getPilot(), host: bulb.address, port: WiZCodec.port, timeout: 1.5)
                    let device = DiscoveredDevice(
                        vendor: .wiz,
                        address: bulb.address,
                        identifier: bulb.mac,
                        model: config.flatMap { $0 }.flatMap(WiZCodec.parseSystemConfig)?.moduleName,
                        state: pilot.flatMap { $0 }.flatMap(WiZCodec.parsePilot))
                    return (index, device)
                }
            }
            var results: [(Int, DiscoveredDevice)] = []
            for await item in group { results.append(item) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
