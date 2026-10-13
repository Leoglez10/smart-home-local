import Foundation

/// Pure message building/parsing for CozyLife local discovery (UDP 6095).
/// Source: cozylife/hass_cozylife_local_pull `udp_discover.py` — see docs/protocols.md.
/// Control (TCP 5555) is intentionally not implemented until verified on the real device.
public enum CozyLifeCodec {
    public static let discoveryPort: UInt16 = 6095

    public struct DeviceInfo: Equatable, Sendable {
        public var deviceId: String
        public var productId: String
        public var deviceType: String?
        public var mac: String?
        public var softwareVersion: String?
    }

    public static func discoveryProbe(sequence: String) -> Data {
        Data(#"{"cmd":0,"pv":0,"sn":"\#(sequence)","msg":{}}"#.utf8)
    }

    /// Applies the same validation as the official integration.
    public static func parseDiscoveryReply(_ data: Data, expectedSequence: String) -> DeviceInfo? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              intValue(object["cmd"]) == 0, intValue(object["pv"]) == 0, intValue(object["res"]) == 0,
              object["sn"] as? String == expectedSequence,
              let msg = object["msg"] as? [String: Any],
              let did = msg["did"] as? String, !did.isEmpty,
              let pid = msg["pid"] as? String, !pid.isEmpty else { return nil }
        return DeviceInfo(
            deviceId: did,
            productId: pid,
            deviceType: msg["dtp"] as? String,
            mac: msg["mac"] as? String,
            softwareVersion: msg["sv"] as? String
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.intValue
    }
}
