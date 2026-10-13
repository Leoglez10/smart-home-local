import Foundation
import Testing
@testable import SmartHomeCore

@Suite struct CozyLifeCodecTests {
    @Test func discoveryProbeMatchesOfficialIntegration() throws {
        let data = CozyLifeCodec.discoveryProbe(sequence: "1636463553873")
        #expect(String(decoding: data, as: UTF8.self) == #"{"cmd":0,"pv":0,"sn":"1636463553873","msg":{}}"#)
    }

    @Test func parsesDocumentedDiscoveryReply() throws {
        let reply = Data(#"{"cmd":0,"pv":0,"sn":"1636463553873","msg":{"did":"629168597cb94c4c1d8f","dtp":"02","pid":"e2s64v","mac":"7cb94c4c1d8f","ip":"192.168.123.57","rssi":-33,"sv":"1.0.0","hv":"0.0.1"},"res":0}"#.utf8)
        let info = try #require(CozyLifeCodec.parseDiscoveryReply(reply, expectedSequence: "1636463553873"))
        #expect(info.deviceId == "629168597cb94c4c1d8f")
        #expect(info.productId == "e2s64v")
        #expect(info.deviceType == "02")
        #expect(info.mac == "7cb94c4c1d8f")
        #expect(info.softwareVersion == "1.0.0")
    }

    @Test func rejectsReplyWithWrongSequenceOrResultOrMissingIds() {
        let wrongSn = Data(#"{"cmd":0,"pv":0,"sn":"999","msg":{"did":"a","pid":"b"},"res":0}"#.utf8)
        let failed = Data(#"{"cmd":0,"pv":0,"sn":"1","msg":{"did":"a","pid":"b"},"res":1}"#.utf8)
        let noPid = Data(#"{"cmd":0,"pv":0,"sn":"1","msg":{"did":"a"},"res":0}"#.utf8)
        #expect(CozyLifeCodec.parseDiscoveryReply(wrongSn, expectedSequence: "1") == nil)
        #expect(CozyLifeCodec.parseDiscoveryReply(failed, expectedSequence: "1") == nil)
        #expect(CozyLifeCodec.parseDiscoveryReply(noPid, expectedSequence: "1") == nil)
        #expect(CozyLifeCodec.parseDiscoveryReply(Data("x".utf8), expectedSequence: "1") == nil)
    }
}
