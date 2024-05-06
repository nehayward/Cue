import Foundation
import SWXMLHash

public struct ZoneGroupMember: XMLObjectDeserialization {
    public let UUID: String
    public let location: String
    public let zoneName: String
    public let invisible: Bool
    public let info: String
    public var wirelessMode: Int
    public var wirelessLeafOnly: Bool
    public var behindWifiExtender: Bool
    public var wifiEnabled: Bool
    public var ethernetEnabled: Bool
    public var voiceConfigState: Int
    public var micEnabled: Bool
    public var airPlayEnabled: Bool

    public static func deserialize(_ node: XMLIndexer) throws -> ZoneGroupMember {
        return try ZoneGroupMember(
            UUID: node.value(ofAttribute: "UUID"),
            location: node.value(ofAttribute: "Location"),
            zoneName: node.value(ofAttribute: "ZoneName"),
            invisible: node.value(ofAttribute: "Invisible") ?? false,
            info: node.value(ofAttribute: "MoreInfo"),
            wirelessMode: node.value(ofAttribute: "WirelessMode"),
            wirelessLeafOnly: node.value(ofAttribute: "WirelessLeafOnly"),
            behindWifiExtender: node.value(ofAttribute: "BehindWifiExtender"),
            wifiEnabled: node.value(ofAttribute: "WifiEnabled"),
            ethernetEnabled: node.value(ofAttribute: "EthLink"),
            voiceConfigState: node.value(ofAttribute: "VoiceConfigState"),
            micEnabled: node.value(ofAttribute: "MicEnabled"),
            airPlayEnabled: node.value(ofAttribute: "AirPlayEnabled")
        )
    }
}
