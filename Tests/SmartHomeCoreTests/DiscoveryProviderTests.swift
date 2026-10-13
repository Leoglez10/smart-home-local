import Foundation
import Testing
@testable import SmartHomeCore

/// In-memory UDP transport: no sockets, deterministic replies.
final class FakeUDPTransport: UDPTransport, @unchecked Sendable {
    let broadcastReplies: [Datagram]
    /// Request payload (UTF-8 string) -> reply. Missing key = timeout (nil).
    let requestReplies: [String: Data]
    private let lock = NSLock()
    private(set) var broadcasts: [(payload: Data, port: UInt16)] = []
    private(set) var requests: [(payload: Data, host: String, port: UInt16)] = []

    init(broadcastReplies: [Datagram], requestReplies: [String: Data] = [:]) {
        self.broadcastReplies = broadcastReplies
        self.requestReplies = requestReplies
    }

    func broadcast(_ payload: Data, port: UInt16, sends: Int, interval: TimeInterval, listen: TimeInterval) async throws -> [Datagram] {
        lock.withLock { broadcasts.append((payload, port)) }
        return broadcastReplies
    }

    func request(_ payload: Data, host: String, port: UInt16, timeout: TimeInterval) async throws -> Data? {
        lock.withLock { requests.append((payload, host, port)) }
        return requestReplies[String(decoding: payload, as: UTF8.self)]
    }
}

private func d(_ s: String) -> Data { Data(s.utf8) }

@Suite struct WiZDiscoveryProviderTests {
    @Test func discoversBulbWithModelAndStateUsingOnlyReadOnlyMethods() async throws {
        let reg = d(#"{"method":"registration","env":"pro","result":{"mac":"a8bb50aabbcc","success":true}}"#)
        let transport = FakeUDPTransport(
            broadcastReplies: [
                Datagram(payload: reg, sender: "192.168.1.35"),
                Datagram(payload: reg, sender: "192.168.1.35"),          // duplicate (probe is resent)
                Datagram(payload: d("garbage"), sender: "192.168.1.99"), // ignored
            ],
            requestReplies: [
                String(decoding: WiZCodec.getSystemConfig(), as: UTF8.self):
                    d(#"{"method":"getSystemConfig","result":{"mac":"a8bb50aabbcc","moduleName":"ESP01_SHRGB1C_31","fwVersion":"1.21.0"}}"#),
                String(decoding: WiZCodec.getPilot(), as: UTF8.self):
                    d(#"{"method":"getPilot","result":{"state":true,"dimming":70,"temp":2700}}"#),
            ]
        )
        let devices = try await WiZDiscoveryProvider(transport: transport).discover(timeout: 1)

        #expect(devices == [DiscoveredDevice(
            vendor: .wiz, address: "192.168.1.35", identifier: "a8bb50aabbcc",
            model: "ESP01_SHRGB1C_31", state: DeviceState(isOn: true, brightness: 70, colorTemperature: 2700))])
        #expect(transport.broadcasts.map(\.port) == [38899])
        #expect(transport.broadcasts.first?.payload == WiZCodec.discoveryProbe())
        // Never sends setPilot during discovery.
        let methods = transport.requests.map { String(decoding: $0.payload, as: UTF8.self) }
        #expect(methods.allSatisfy { !$0.contains("setPilot") })
        #expect(transport.requests.allSatisfy { $0.host == "192.168.1.35" && $0.port == 38899 })
    }

    @Test func keepsBulbWhenDetailQueriesTimeOut() async throws {
        let reg = d(#"{"method":"registration","result":{"mac":"a8bb50aabbcc"}}"#)
        let transport = FakeUDPTransport(broadcastReplies: [Datagram(payload: reg, sender: "10.0.0.2")])
        let devices = try await WiZDiscoveryProvider(transport: transport).discover(timeout: 1)
        #expect(devices == [DiscoveredDevice(vendor: .wiz, address: "10.0.0.2", identifier: "a8bb50aabbcc", model: nil, state: nil)])
    }
}

@Suite struct CozyLifeDiscoveryProviderTests {
    @Test func discoversDeviceMatchingSequenceOnPort6095() async throws {
        let ok = d(#"{"cmd":0,"pv":0,"sn":"42","msg":{"did":"629168597cb94c4c1d8f","dtp":"01","pid":"e2s64v"},"res":0}"#)
        let stale = d(#"{"cmd":0,"pv":0,"sn":"41","msg":{"did":"other","pid":"x"},"res":0}"#)
        let transport = FakeUDPTransport(broadcastReplies: [
            Datagram(payload: ok, sender: "192.168.1.42"),
            Datagram(payload: ok, sender: "192.168.1.42"),
            Datagram(payload: stale, sender: "192.168.1.43"),
        ])
        let devices = try await CozyLifeDiscoveryProvider(transport: transport, sequence: { "42" }).discover(timeout: 1)

        #expect(devices == [DiscoveredDevice(vendor: .cozyLife, address: "192.168.1.42",
                                             identifier: "629168597cb94c4c1d8f", model: "e2s64v", state: nil)])
        #expect(transport.broadcasts.map(\.port) == [6095])
        #expect(transport.broadcasts.first?.payload == CozyLifeCodec.discoveryProbe(sequence: "42"))
        #expect(transport.requests.isEmpty) // no TCP/UDP control until verified on the device
    }
}

struct StubProvider: DiscoveryProvider {
    let vendor: Vendor
    let result: Result<[DiscoveredDevice], SmartDeviceError>
    func discover(timeout: TimeInterval) async throws -> [DiscoveredDevice] { try result.get() }
}

@Suite struct DiscoveryServiceTests {
    @Test func aggregatesProvidersAndReportsFailuresWithoutDroppingOthers() async {
        let wiz = DiscoveredDevice(vendor: .wiz, address: "10.0.0.2", identifier: "m", model: nil, state: nil)
        let service = DiscoveryService(providers: [
            StubProvider(vendor: .wiz, result: .success([wiz])),
            StubProvider(vendor: .cozyLife, result: .failure(.transport("boom"))),
        ])
        let outcome = await service.discover(timeout: 1)
        #expect(outcome.devices == [wiz])
        #expect(outcome.failures == [.cozyLife: "transport(\"boom\")"])
        #expect(service.vendors == [.wiz, .cozyLife])
    }
}
