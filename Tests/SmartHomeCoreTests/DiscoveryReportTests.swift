import Testing
@testable import SmartHomeCore

@Suite struct DiscoveryReportTests {
    @Test func rendersRequestedFormatGroupedByVendor() {
        let devices = [
            DiscoveredDevice(vendor: .wiz, address: "192.168.1.35", identifier: "a8bb50aabbcc", model: "ESP01_SHRGB1C_31", state: DeviceState(isOn: true)),
            DiscoveredDevice(vendor: .cozyLife, address: "192.168.1.42", identifier: "629168597cb94c4c1d8f", model: "e2s64v", state: DeviceState(isOn: false)),
        ]
        let expected = """
        Smart Home Discovery

        [WiZ]
        192.168.1.35
        Model: ESP01_SHRGB1C_31
        State: ON

        [CozyLife]
        192.168.1.42
        Model: e2s64v
        State: OFF

        """
        #expect(DiscoveryReport.render(devices, searched: [.wiz, .cozyLife]) == expected)
    }

    @Test func reportsVendorsWithNoDevicesAndUnknownState() {
        let devices = [DiscoveredDevice(vendor: .wiz, address: "10.0.0.2", identifier: "x", model: nil, state: nil)]
        let expected = """
        Smart Home Discovery

        [WiZ]
        10.0.0.2
        Model: unknown
        State: unknown

        [CozyLife]
        (no devices found)

        """
        #expect(DiscoveryReport.render(devices, searched: [.wiz, .cozyLife]) == expected)
    }
}
