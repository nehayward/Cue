
public struct TidalResult: Codable {
    public let albums: [TidalAlbumEntry]
    public let artists: [TidalArtistEntry]
    public let tracks: [TidalTrackEntry]
}
