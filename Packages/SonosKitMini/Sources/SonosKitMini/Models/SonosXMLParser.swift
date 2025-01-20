//
//  SonosXMLParser.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/21/24.
//


import Foundation

class SonosXMLParser: NSObject, XMLParserDelegate {
    private var currentGroup: SonosGroup?
    private var currentRoom: SonosRoom?
    private var currentElement = ""
    private var groups: [SonosGroup] = []
    private var rooms: [SonosRoom] = []
    
    func parse(data: Data) -> [SonosGroup] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return groups
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        currentElement = elementName

        switch elementName {
        case "ZoneGroup":
            if let id = attributeDict["ID"], let coordinator = attributeDict["Coordinator"] {
                currentGroup = SonosGroup(
                    id: id,
                    coordinatorID: coordinator,
                    rooms: [],
                    coordinatorRoom: SonosRoom(id: coordinator, ip: "", name: "")
                )
            }
        case "ZoneGroupMember":
            if let uuid = attributeDict["UUID"],
               let location = attributeDict["Location"],
               let name = attributeDict["ZoneName"],
               let softwareVersion = attributeDict["SoftwareVersion"] {
                let ip = URL(string: location)?.host ?? ""
                let isCoordinator = (uuid == currentGroup?.coordinatorID)
                currentRoom = SonosRoom(id: uuid, ip: ip, name: name)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "ZoneGroupMember":
            if let room = currentRoom {
                rooms.append(room)
                currentRoom = nil
            }
        case "ZoneGroup":
            if var group = currentGroup {
                group.rooms = rooms
                if let coordinatorRoom = rooms.first(where: { $0.id == group.coordinatorID }) {
                    group.coordinatorRoom = coordinatorRoom
                }
                groups.append(group)
                rooms.removeAll()
                currentGroup = nil
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Handle any inner text if needed.
    }
}
