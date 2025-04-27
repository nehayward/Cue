//
//  Parser.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/22/24.
//
import Foundation

public struct ZoneGroupMember {
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

    public init(
        UUID: String,
        location: String,
        zoneName: String,
        channelMap: String?,
        satChannelMap: String?,
        invisible: Bool,
        info: String,
        wirelessMode: Int,
        wirelessLeafOnly: Bool,
        behindWifiExtender: Bool,
        wifiEnabled: Bool,
        ethernetEnabled: Bool,
        voiceConfigState: Int,
        micEnabled: Bool,
        airPlayEnabled: Bool,
        satellites: [ZoneGroupMember]
    ) {
        self.UUID = UUID
        self.location = location
        self.zoneName = zoneName
        self.channelMap = channelMap
        self.satChannelMap = satChannelMap
        self.invisible = invisible
        self.info = info
        self.wirelessMode = wirelessMode
        self.wirelessLeafOnly = wirelessLeafOnly
        self.behindWifiExtender = behindWifiExtender
        self.wifiEnabled = wifiEnabled
        self.ethernetEnabled = ethernetEnabled
        self.voiceConfigState = voiceConfigState
        self.micEnabled = micEnabled
        self.airPlayEnabled = airPlayEnabled
        self.satellites = satellites
    }
}

struct ZoneGroup {
    let coordinator: String
    let id: String
    var members: [ZoneGroupMember]
}


final class ZoneGroupStateParser: NSObject, XMLParserDelegate {
    var zoneGroups: [ZoneGroup] = []
    var currentGroup: ZoneGroup?
    var currentMember: ZoneGroupMember?
    var currentSatellites: [ZoneGroupMember] = []
    var currentElement = ""
    
    func parse(xml: String) -> [ZoneGroup] {
        let xmlData = xml.unescaped.ampersandSafe.data(using: .utf8)!
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.parse()
        return zoneGroups
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "ZoneGroup" {
            let coordinator = attributeDict["Coordinator"] ?? ""
            let id = attributeDict["ID"] ?? ""
            currentGroup = ZoneGroup(coordinator: coordinator, id: id, members: [])
        } else if elementName == "ZoneGroupMember" {
            // Reset satellites array for new member
            currentSatellites = []
            let name = (attributeDict["ZoneName"] ?? "").replacingOccurrences(of: "%26", with: "&")
            let uuid = attributeDict["UUID"] ?? ""
            let location = attributeDict["Location"] ?? ""
            let info = attributeDict["MoreInfo"] ?? ""
            let wirelessMode = Int(attributeDict["WirelessMode"] ?? "")
            let wirelessLeafOnly = attributeDict["WirelessLeafOnly"].map { $0 == "1" } ?? false
            let behindWifiExtender = attributeDict["BehindWifiExtender"].map { $0 == "1" } ?? false
            let wifiEnabled = attributeDict["WifiEnabled"].map { $0 == "1" } ?? false
            let ethernetEnabled = attributeDict["EthLink"].map { $0 == "1" } ?? false
            let voiceConfigState = Int(attributeDict["VoiceConfigState"] ?? "")
            let micEnabled = attributeDict["MicEnabled"].map { $0 == "1" } ?? false
            let airPlayEnabled = attributeDict["AirPlayEnabled"].map { $0 == "1" } ?? false
            
            let channelMap = attributeDict["ChannelMapSet"]
            let satChannelMap = attributeDict["HTSatChanMapSet"]
            let invisible = attributeDict["Invisible"].map { $0 == "1" } ?? false
            
            currentMember = ZoneGroupMember(
                UUID: uuid,
                location: location,
                zoneName: name,
                channelMap: channelMap,
                satChannelMap: satChannelMap,
                invisible: invisible,
                info: info,
                wirelessMode: wirelessMode ?? 0,
                wirelessLeafOnly: wirelessLeafOnly,
                behindWifiExtender: behindWifiExtender,
                wifiEnabled: wifiEnabled,
                ethernetEnabled: ethernetEnabled,
                voiceConfigState: voiceConfigState ?? 0,
                micEnabled: micEnabled,
                airPlayEnabled: airPlayEnabled,
                satellites: [] // Will be populated with currentSatellites when the member ends
            )
        } else if elementName == "Satellite" {
            let uuid = attributeDict["UUID"] ?? ""
            let location = attributeDict["Location"] ?? ""
            let zoneName = (attributeDict["ZoneName"] ?? "").replacingOccurrences(of: "%26", with: "&")
            let info = attributeDict["MoreInfo"] ?? ""
            let wirelessMode = Int(attributeDict["WirelessMode"] ?? "")
            let wirelessLeafOnly = attributeDict["WirelessLeafOnly"].map { $0 == "1" } ?? false
            let behindWifiExtender = attributeDict["BehindWifiExtender"].map { $0 == "1" } ?? false
            let wifiEnabled = attributeDict["WifiEnabled"].map { $0 == "1" } ?? false
            let ethernetEnabled = attributeDict["EthLink"].map { $0 == "1" } ?? false
            let voiceConfigState = Int(attributeDict["VoiceConfigState"] ?? "")
            let micEnabled = attributeDict["MicEnabled"].map { $0 == "1" } ?? false
            let airPlayEnabled = attributeDict["AirPlayEnabled"].map { $0 == "1" } ?? false
            
            let channelMap = attributeDict["ChannelMapSet"]
            let satChannelMap = attributeDict["HTSatChanMapSet"]
            let invisible = attributeDict["Invisible"].map { $0 == "1" } ?? false
            
            let satellite = ZoneGroupMember(
                UUID: uuid,
                location: location,
                zoneName: zoneName,
                channelMap: channelMap,
                satChannelMap: satChannelMap,
                invisible: invisible,
                info: info,
                wirelessMode: wirelessMode ?? 0,
                wirelessLeafOnly: wirelessLeafOnly,
                behindWifiExtender: behindWifiExtender,
                wifiEnabled: wifiEnabled,
                ethernetEnabled: ethernetEnabled,
                voiceConfigState: voiceConfigState ?? 0,
                micEnabled: micEnabled,
                airPlayEnabled: airPlayEnabled,
                satellites: [] // Satellites don't have their own satellites
            )
            
            currentSatellites.append(satellite)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "ZoneGroupMember", var member = currentMember {
            member.satellites = currentSatellites // Add collected satellites to the member
            currentGroup?.members.append(member)
            currentMember = nil
            currentSatellites = []
        } else if elementName == "ZoneGroup", let group = currentGroup {
            zoneGroups.append(group)
            currentGroup = nil
        }
    }
}
