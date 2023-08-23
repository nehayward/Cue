import Foundation
import SWXMLHash

public struct TrackXML {
    public let title: String


    public static func deserialize(_ node: XMLIndexer) throws -> TrackXML {
        return try TrackXML(
            title: node.value(ofAttribute: "dc:title")
        )
    }

//    init(element: XMLElement?) {
//        print(element)
//        title = ""
//    }
}
