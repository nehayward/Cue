import Foundation
import SWXMLHash

public struct RendererControl: XMLObjectDeserialization {
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
