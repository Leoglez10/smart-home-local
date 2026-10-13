import Foundation

/// Pure message building/parsing for the WiZ local UDP protocol (port 38899).
/// Source: pywizlight `discovery.py` / `bulb.py` — see docs/protocols.md.
public enum WiZCodec {
    public static let port: UInt16 = 38899

    public struct SystemInfo: Equatable, Sendable {
        public var mac: String?
        public var moduleName: String?
        public var firmware: String?
    }

    /// Exact pywizlight probe. `register:false` asks the bulb not to push state to us.
    public static func discoveryProbe() -> Data {
        Data(#"{"method":"registration","params":{"phoneMac":"AAAAAAAAAAAA","register":false,"phoneIp":"1.2.3.4","id":"1"}}"#.utf8)
    }

    public static func getPilot() -> Data { request("getPilot") }
    public static func getSystemConfig() -> Data { request("getSystemConfig") }

    /// Returns the bulb MAC from a `registration` reply, or nil.
    public static func parseDiscoveryReply(_ data: Data) -> String? {
        guard let object = json(data), object["method"] as? String == "registration",
              let result = object["result"] as? [String: Any],
              let mac = result["mac"] as? String, !mac.isEmpty else { return nil }
        return mac
    }

    public static func parsePilot(_ data: Data) -> DeviceState? {
        guard let result = result(data, method: "getPilot") else { return nil }
        var state = DeviceState()
        state.isOn = result["state"] as? Bool
        state.brightness = result["dimming"] as? Int
        if let r = result["r"] as? Int, let g = result["g"] as? Int, let b = result["b"] as? Int {
            state.color = RGBColor(red: r, green: g, blue: b)
        }
        state.colorTemperature = result["temp"] as? Int
        return state
    }

    public static func parseSystemConfig(_ data: Data) -> SystemInfo? {
        guard let result = result(data, method: "getSystemConfig") else { return nil }
        return SystemInfo(
            mac: result["mac"] as? String,
            moduleName: result["moduleName"] as? String,
            firmware: result["fwVersion"] as? String
        )
    }

    // MARK: - Helpers

    private static func request(_ method: String) -> Data {
        Data(#"{"method":"\#(method)","params":{}}"#.utf8)
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func result(_ data: Data, method: String) -> [String: Any]? {
        guard let object = json(data), object["method"] as? String == method,
              object["error"] == nil else { return nil }
        return object["result"] as? [String: Any]
    }
}
