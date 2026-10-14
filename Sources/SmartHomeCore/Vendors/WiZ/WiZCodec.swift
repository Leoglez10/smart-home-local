import Foundation
import CoreFoundation

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
    public static func getModelConfig() -> Data { request("getModelConfig") }
    public static func getUserConfig() -> Data { request("getUserConfig") }

    /// Range keys follow pywizlight; never invent a default for an unknown model.
    public static func parseTemperatureRange(_ data: Data, method: String) -> ClosedRange<Int>? {
        guard ["getModelConfig", "getUserConfig"].contains(method),
              let config = result(data, method: method) else { return nil }
        for key in ["cctRange", "extRange", "whiteRange"] {
            guard let values = config[key] as? [Any], values.count >= 2 else { continue }
            let integers = values.compactMap(integer)
            guard integers.count == values.count, integers.allSatisfy({ $0 > 0 }),
                  let lower = integers.min(), let upper = integers.max(), lower < upper else { continue }
            return lower...upper
        }
        return nil
    }

    /// Only the driver constructs params, after capability and value validation.
    static func setPilot(_ params: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["method": "setPilot", "params": params], options: [.sortedKeys])
    }

    /// A matching method alone is insufficient: require the JSON boolean true and no error.
    public static func parseSetPilotACK(_ data: Data) -> Bool {
        guard let reply = result(data, method: "setPilot"),
              let value = reply["success"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }

    /// Returns the bulb MAC from a `registration` reply, or nil.
    public static func parseDiscoveryReply(_ data: Data) -> String? {
        guard let object = json(data), object["method"] as? String == "registration",
              let result = object["result"] as? [String: Any],
              let mac = result["mac"] as? String, !mac.isEmpty else { return nil }
        return mac
    }

    public static func parsePilot(_ data: Data) -> DeviceState? {
        guard result(data, method: "getPilot") != nil,
              let reply = try? JSONDecoder().decode(PilotReply.self, from: data) else { return nil }
        let pilot = reply.result
        if let brightness = pilot.dimming, !(0...100).contains(brightness) { return nil }
        if let temperature = pilot.temp, temperature <= 0 { return nil }
        guard [pilot.r, pilot.g, pilot.b].compactMap({ $0 }).allSatisfy({ (0...255).contains($0) }) else { return nil }
        var state = DeviceState(isOn: pilot.state, brightness: pilot.dimming, colorTemperature: pilot.temp)
        if let r = pilot.r, let g = pilot.g, let b = pilot.b {
            state.color = RGBColor(red: r, green: g, blue: b)
        }
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

    // Typed decoding rejects JSON numbers posing as booleans, strings as integers, etc.
    private struct PilotReply: Decodable {
        let result: Pilot
        struct Pilot: Decodable {
            let state: Bool?
            let dimming: Int?
            let r: Int?
            let g: Int?
            let b: Int?
            let temp: Int?
        }
    }

    private static func request(_ method: String) -> Data {
        Data(#"{"method":"\#(method)","params":{}}"#.utf8)
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = value as? Int, number.doubleValue == Double(integer) else { return nil }
        return integer
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
