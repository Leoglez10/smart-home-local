import Foundation

/// CozyLife discovery: broadcast `{"cmd":0,...}` on UDP 6095 (official integration).
/// Discovery only; TCP 5555 control stays disabled until verified on the real device.
public struct CozyLifeDiscoveryProvider: DiscoveryProvider {
    public let vendor: Vendor = .cozyLife
    private let transport: any UDPTransport
    private let sequence: @Sendable () -> String

    public init(
        transport: any UDPTransport = BSDUDPTransport(),
        sequence: @escaping @Sendable () -> String = { String(Int(Date().timeIntervalSince1970 * 1000)) }
    ) {
        self.transport = transport
        self.sequence = sequence
    }

    public func discover(timeout: TimeInterval) async throws -> [DiscoveredDevice] {
        let sn = sequence()
        let replies = try await transport.broadcast(
            CozyLifeCodec.discoveryProbe(sequence: sn), port: CozyLifeCodec.discoveryPort,
            sends: 3, interval: 0.03, listen: timeout)

        var devices: [DiscoveredDevice] = []
        for reply in replies where !devices.contains(where: { $0.address == reply.sender }) {
            guard let info = CozyLifeCodec.parseDiscoveryReply(reply.payload, expectedSequence: sn) else { continue }
            devices.append(DiscoveredDevice(
                vendor: .cozyLife, address: reply.sender, identifier: info.deviceId,
                model: info.productId, state: nil))
        }
        return devices
    }
}
