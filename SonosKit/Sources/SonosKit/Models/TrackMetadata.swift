import Foundation
//import SWXMLHash
//
//public struct PositionInfo: XMLObjectDeserialization {
//    public let trackMetadata:
//    public let zoneGroupMembers: [ZoneGroupMember]
//
//    public static func deserialize(_ node: XMLIndexer) throws -> ZoneGroup {
//        return try ZoneGroup(
//            ID: node.value(ofAttribute: "ID"),
//            coordinator: node.value(ofAttribute: "Coordinator"),
//            zoneGroupMembers: node.filterChildren { elem, index in
//                elem.name == "ZoneGroupMember"
//            }.children.map { try $0.value() }
//        )
//    }
//}


public struct Track {
    public let name: String
    public let artist: String
    public let album: String

    public init(name: String, artist: String, album: String) {
        self.name = name
        self.artist = artist
        self.album = album
    }
}
