import Foundation

public struct AppleLibraryContainer: Codable {
    public let data: [AppleLibraryItem]
    public let meta: AppleLibraryItem.Meta?
    public let next: String?
}

public struct AppleLibraryItem: Codable {
    public let id: String
    public let href: String
    public let type: String
    public let attributes: Attributes
}

extension AppleLibraryItem {
    public struct Attributes: Codable {
        public let name: String
        public let artwork: Artwork?
        public let playParams: PlayParameters?
//        public let isPubic: Bool
//        public let dateAdded: Date
//        public let lastModifiedDate: Date
    }

    public struct Artwork: Codable {
        public let url: URL?
        public func urlWithSize(width: Int, height: Int) -> URL? {
            guard let url = url?.absoluteString.removingPercentEncoding else { return nil }
            let widthPlaceholder = "{w}"
            let heightPlaceholder = "{h}"
            return URL(string: url.replacingOccurrences(of: widthPlaceholder, with: "\(width)")
                .replacingOccurrences(of: heightPlaceholder, with: "\(height)"))
        }
    }

    public struct Meta: Codable {
        public let total: Int
    }

    public struct PlayParameters: Codable {
        public let catalogID: String?
        public let id: String
        public let kind: String
    }
}
