// Define the Resource structure
public struct TidalTrackResource: Codable {
    public let id: String
    public let isrc: String?
    public let title: String
    public let artists: [TidalArtistResource]
    public let album: TidalAlbumResource?
    public let duration: Int
    public let releaseDate: String?
    public let imageCover: [TidalImage]?
    public let numberOfVolumes: Int?
    public let numberOfTracks: Int?
    public let numberOfVideos: Int?
    public let copyright: Copyright?
    public let tidalUrl: String
    public let mediaMetadata: [String]?
    public let isExplicit: Bool
    public let popularity: Double
}
