import Foundation

public struct PlayableContentMetadata: Equatable, Codable, Hashable {
    public let duration: Duration?
    public let popularity: Int?
    public let artist: String?
    public let artistID: String?
    public let album: String?
    public let albumID: String?

    init(duration: Duration? = nil, popularity: Int? = nil, artist: String? = nil, artistID: String? = nil, album: String? = nil, albumID: String? = nil) {
        self.duration = duration
        self.popularity = popularity
        self.artist = artist
        self.artistID = artistID
        self.album = album
        self.albumID = albumID
    }
}
