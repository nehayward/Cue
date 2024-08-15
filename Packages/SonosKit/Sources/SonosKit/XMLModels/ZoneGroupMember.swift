import Foundation
import SWXMLHash

public struct ZoneGroupMember: XMLObjectDeserialization {
    public let UUID: String
    public let location: String
    public let zoneName: String
    public let channelMap: String?
    public let satChannelMap: String?
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
    public var satellites: [ZoneGroupMember]

    public static func deserialize(_ node: XMLIndexer) throws -> ZoneGroupMember {
        let satellites: [ZoneGroupMember] = try node.filterChildren { elem, index in
            elem.name == "Satellite"
        }.children.map {
            try $0.value()
        }

        return try ZoneGroupMember(
            UUID: node.value(ofAttribute: "UUID"),
            location: node.value(ofAttribute: "Location"),
            zoneName: node.value(ofAttribute: "ZoneName"),
            channelMap: node.value(ofAttribute: "ChannelMapSet"),
            satChannelMap: node.value(ofAttribute: "HTSatChanMapSet"),
            invisible: node.value(ofAttribute: "Invisible") ?? false,
            info: node.value(ofAttribute: "MoreInfo"),
            wirelessMode: node.value(ofAttribute: "WirelessMode"),
            wirelessLeafOnly: node.value(ofAttribute: "WirelessLeafOnly"),
            behindWifiExtender: node.value(ofAttribute: "BehindWifiExtender"),
            wifiEnabled: node.value(ofAttribute: "WifiEnabled"),
            ethernetEnabled: node.value(ofAttribute: "EthLink") ?? false,
            voiceConfigState: node.value(ofAttribute: "VoiceConfigState"),
            micEnabled: node.value(ofAttribute: "MicEnabled"),
            airPlayEnabled: node.value(ofAttribute: "AirPlayEnabled"),
            satellites: satellites
        )
    }
}
