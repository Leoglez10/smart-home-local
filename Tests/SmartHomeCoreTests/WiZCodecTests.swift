import Foundation
import Testing
@testable import SmartHomeCore

@Suite struct WiZCodecTests {
    @Test func discoveryProbeMatchesPywizlightRegistrationMessage() throws {
        let data = WiZCodec.discoveryProbe()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["method"] as? String == "registration")
        let params = try #require(object["params"] as? [String: Any])
        #expect(params["register"] as? Bool == false)
        #expect(params["phoneMac"] as? String == "AAAAAAAAAAAA")
        #expect(params["phoneIp"] as? String == "1.2.3.4")
        #expect(params["id"] as? String == "1")
    }

    @Test func readOnlyRequestsHaveMethodAndEmptyParams() throws {
        for (data, method) in [(WiZCodec.getPilot(), "getPilot"), (WiZCodec.getSystemConfig(), "getSystemConfig")] {
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["method"] as? String == method)
            #expect((object["params"] as? [String: Any])?.isEmpty == true)
        }
    }

    @Test func parsesDiscoveryReplyMac() {
        let reply = Data(#"{"method":"registration","env":"pro","result":{"mac":"a8bb50aabbcc","success":true}}"#.utf8)
        #expect(WiZCodec.parseDiscoveryReply(reply) == "a8bb50aabbcc")
    }

    @Test func rejectsDiscoveryReplyWithoutMacOrInvalidJSON() {
        #expect(WiZCodec.parseDiscoveryReply(Data(#"{"method":"registration","result":{}}"#.utf8)) == nil)
        #expect(WiZCodec.parseDiscoveryReply(Data("not json".utf8)) == nil)
        #expect(WiZCodec.parseDiscoveryReply(Data(#"{"method":"getPilot","result":{"mac":"x"}}"#.utf8)) == nil)
    }

    @Test func parsesPilotStateWithColor() throws {
        let reply = Data(#"{"method":"getPilot","env":"pro","result":{"mac":"a8bb50aabbcc","rssi":-55,"state":true,"sceneId":0,"r":255,"g":0,"b":0,"c":0,"w":0,"dimming":70}}"#.utf8)
        let state = try #require(WiZCodec.parsePilot(reply))
        #expect(state.isOn == true)
        #expect(state.brightness == 70)
        #expect(state.color == RGBColor(red: 255, green: 0, blue: 0))
        #expect(state.colorTemperature == nil)
    }

    @Test func parsesPilotStateWithTemperature() throws {
        let reply = Data(#"{"method":"getPilot","result":{"state":false,"temp":2700,"dimming":10}}"#.utf8)
        let state = try #require(WiZCodec.parsePilot(reply))
        #expect(state.isOn == false)
        #expect(state.colorTemperature == 2700)
        #expect(state.color == nil)
    }

    @Test func pilotParseRejectsErrorReply() {
        let reply = Data(#"{"method":"getPilot","error":{"code":-32601,"message":"Method not found"}}"#.utf8)
        #expect(WiZCodec.parsePilot(reply) == nil)
    }

    @Test func parsesSystemConfigModel() throws {
        let reply = Data(#"{"method":"getSystemConfig","result":{"mac":"a8bb50aabbcc","homeId":1,"moduleName":"ESP01_SHRGB1C_31","fwVersion":"1.21.0","typeId":0}}"#.utf8)
        let info = try #require(WiZCodec.parseSystemConfig(reply))
        #expect(info.moduleName == "ESP01_SHRGB1C_31")
        #expect(info.firmware == "1.21.0")
        #expect(info.mac == "a8bb50aabbcc")
    }
}
