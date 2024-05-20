// Define the Resource structure
public struct TidalTrackResource: Codable {
    public let id: String
    public let barcodeId: String?
    public let title: String
    public let artists: [TidalArtistResource]
    public let album: TidalAlbum
    public let duration: Int
    public let releaseDate: String?
    public let imageCover: [TidalImage]?
    public let numberOfVolumes: Int?
    public let numberOfTracks: Int?
    public let numberOfVideos: Int?
    public let copyright: String?
    public let tidalUrl: String
}
