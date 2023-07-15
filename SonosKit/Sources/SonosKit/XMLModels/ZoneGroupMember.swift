import Foundation
import SWXMLHash

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
