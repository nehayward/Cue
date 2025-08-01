import Foundation

public struct SoundCloudPlaylist: Codable {
    public let id: Int
    public let title: String
    public let description: String?
    public let duration: Double?
    public let artworkUrl: String?
    public let access: String?
    public let permalinkUrl: String?
    public let user: SoundCloudUser?
    public let genre: String?
    public let trackCount: Int?
    public let likesCount: Int?
    public let repostsCount: Int?
    public let tracks: [SoundCloudTrack]?
    
    public var artworkURLOriginal: URL? {
        guard let artworkUrl = artworkUrl?.replacingOccurrences(of: "large", with: "original"), 
              let artworkURLOriginal = URL(string: artworkUrl) else {
            return nil
        }
        
        return artworkURLOriginal
    }
}
