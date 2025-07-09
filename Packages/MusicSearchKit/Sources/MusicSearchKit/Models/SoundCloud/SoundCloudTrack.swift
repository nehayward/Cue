import Foundation

public struct SoundCloudTrack: Codable {
    public let id: Int
    public let title: String
    public let duration: Double?
    public let releaseYear: Int?
    public let description: String?
    public let artworkUrl: String?
    public let access: String?
    public let metadataArtist: String?
    public let isrc: String?
    public let permalinkUrl: String?
    public let user: SoundCloudUser?
    public let genre: String?
    public let playbackCount: Int?
    public let favoritingsCount: Int?
    public let streamUrl: String?
    
    public var artworkURLOriginal: URL? {
        guard let artworkUrl = artworkUrl?.replacingOccurrences(of: "large", with: "original"), let artworkURLOriginal = URL(string: artworkUrl) else {
            return nil
        }
        
        return artworkURLOriginal
    }
}

public struct SoundCloudUser: Codable {
    public let id: Int
    public let username: String
    public let permalink: String?
    public let avatarUrl: String?
    public let fullName: String?
    public let city: String?
    public let country: String?
    public let description: String?
    public let followersCount: Int?
    public let followingsCount: Int?
    public let trackCount: Int?
    public let playlistCount: Int?
}
