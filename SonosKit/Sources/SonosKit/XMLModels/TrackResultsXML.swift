//import Foundation
//import SWXMLHash
//
//public struct TrackResultsXML: XMLObjectDeserialization {
//    public let tracks: [TrackXML]
//
//    public static func deserialize(_ node: XMLIndexer) throws -> TrackResultsXML {
//        return try TrackResultsXML(
//            tracks: node.filterChildren({ elem, index in
//                elem.name == "item"
//            }). )
//        )
//    }
//}
