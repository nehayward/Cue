public struct SpotifyResult: Decodable, Sendable {
    public let playlists: SpotifyPlaylists?
    public let tracks: SpotifyTracks?
    public let albums: SpotifyAlbums?
    public let artists: SpotifyArtists?
}
