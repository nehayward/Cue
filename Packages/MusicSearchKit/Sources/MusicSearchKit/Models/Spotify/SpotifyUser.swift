import Foundation

public struct SpotifyUser: Decodable {
    public let displayName: String?
    public let href: String?
    public let id: String
    public let images: [SpotifyImage]
    public let type: String
    public let uri: String
}

