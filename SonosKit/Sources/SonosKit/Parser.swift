//import Foundation
//
//// Define a custom class to represent a ZoneGroupMember
//public class ZoneGroupMember {
//    var coordinator: String?
//    var id: String?
//    var uuid: String?
//    var location: String?
//    var zoneName: String?
//    var softwareVersion: String?
//    var channelMapSet: String?
//    // Add more properties as needed
//
//    init() {}
//}
//
//// Create an instance of XMLParser and implement the necessary delegate methods
//class XMLParsingClone: NSObject {
//    var currentElement: String?
//    var zoneGroupMembers: [ZoneGroupMember] = []
//    var currentZoneGroupMember: ZoneGroupMember?
//    
//    
//    func parseThis(data: Data) {
//        let delegate = XMLParsingClone()
//        let parser = XMLParser(data: data)
//        parser.delegate = delegate
//        parser.parse()
//    }
//}
//
//extension XMLParsingClone: XMLParserDelegate {
//    // Called when the parser starts parsing a new element
//    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
//        currentElement = elementName
//
//        if elementName == "ZoneGroupMember" {
//            currentZoneGroupMember = ZoneGroupMember()
//            currentZoneGroupMember?.coordinator = attributeDict["Coordinator"]
//            currentZoneGroupMember?.id = attributeDict["ID"]
//            currentZoneGroupMember?.uuid = attributeDict["UUID"]
//            currentZoneGroupMember?.location = attributeDict["Location"]
//            currentZoneGroupMember?.zoneName = attributeDict["ZoneName"]
//            currentZoneGroupMember?.softwareVersion = attributeDict["SoftwareVersion"]
//            currentZoneGroupMember?.channelMapSet = attributeDict["ChannelMapSet"]
//        }
//    }
//
//    // Called when the parser encounters the characters inside an element
//    func parser(_ parser: XMLParser, foundCharacters string: String) {
//        // Do something with the found characters if needed
//    }
//
//    // Called when the parser finishes parsing an element
//    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
//        if elementName == "ZoneGroupMember" {
//            if let zoneGroupMember = currentZoneGroupMember {
//                zoneGroupMembers.append(zoneGroupMember)
//            }
//            currentZoneGroupMember = nil
//        }
//    }
//
//    // Called when the parsing is complete
//    func parserDidEndDocument(_ parser: XMLParser) {
//        // Process the parsed zoneGroupMembers array or perform any other necessary actions
//        for zoneGroupMember in zoneGroupMembers {
//            print("Coordinator: \(zoneGroupMember.coordinator ?? "")")
//            print("ID: \(zoneGroupMember.id ?? "")")
//            print("UUID: \(zoneGroupMember.uuid ?? "")")
//            print("Location: \(zoneGroupMember.location ?? "")")
//            print("Zone Name: \(zoneGroupMember.zoneName ?? "")")
//            print("Software Version: \(zoneGroupMember.softwareVersion ?? "")")
//            print("Channel Map Set: \(zoneGroupMember.channelMapSet ?? "")")
//            print("---")
//        }
//    }
//}
