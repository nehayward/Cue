import Foundation
import SWXMLHash

public struct ZoneGroup: XMLObjectDeserialization {
    public let ID: String
    public let coordinator: String
    public let zoneGroupMembers: [ZoneGroupMember]

    public static func deserialize(_ node: XMLIndexer) throws -> ZoneGroup {
        return try ZoneGroup(
            ID: node.value(ofAttribute: "ID"),
            coordinator: node.value(ofAttribute: "Coordinator"),
            zoneGroupMembers: node.filterChildren { elem, index in
                elem.name == "ZoneGroupMember"
            }.children.map { try $0.value() }
        )
    }
}

public struct ZoneGroupMember: XMLObjectDeserialization {
    public let UUID: String
    public let location: String
    public let zoneName: String
    public let invisible: Bool

    public static func deserialize(_ node: XMLIndexer) throws -> ZoneGroupMember {
        return try ZoneGroupMember(
            UUID: node.value(ofAttribute: "UUID"),
            location: node.value(ofAttribute: "Location"),
            zoneName: node.value(ofAttribute: "ZoneName"),
            invisible: node.value(ofAttribute: "Invisible") ?? false
        )
    }
}
