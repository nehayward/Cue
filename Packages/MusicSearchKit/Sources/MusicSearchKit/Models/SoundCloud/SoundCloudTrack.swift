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
    
    public var artworkURLOriginal: URL? {
        guard let artworkUrl = artworkUrl?.replacingOccurrences(of: "large", with: "original"), let artworkURLOriginal = URL(string: artworkUrl) else {
            return nil
        }
        
        return artworkURLOriginal
    }
}
