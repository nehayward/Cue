import Foundation

public extension Track {
    struct Metadata {
        public let ISRC: String?
        public let openInURL: URL?
        public let contentType: ContentType?
        public var stationID: String?
    }
}
