import Foundation
import SWXMLHash

public struct ZoneGroup: XMLObjectDeserialization {
    public let ID: String
    public let coordinator: String
    public let zoneGroupMembers: [ZoneGroupMember]

    public static func deserialize(_ node: XMLIndexer) throws -> ZoneGroup {
        let zoneGroupMembers: [ZoneGroupMember] = try node.filterChildren { elem, index in
            elem.name == "ZoneGroupMember"
        }.children.map {
            try $0.value()
        }
        
        return try ZoneGroup(
            ID: node.value(ofAttribute: "ID"),
            coordinator: node.value(ofAttribute: "Coordinator"),
            zoneGroupMembers: zoneGroupMembers
        )
    }
}
