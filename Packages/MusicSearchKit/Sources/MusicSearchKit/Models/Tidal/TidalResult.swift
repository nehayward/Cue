
public struct TidalResult: Codable {
    public let albums: [TidalAlbumResource]
    public let artists: [TidalArtistResource]
    public let tracks: [TidalTrackResource]
    public let playlists: [TidalPlaylistResource]
}
