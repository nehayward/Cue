public struct SpotifyResult: Decodable, Sendable {
    public let playlists: SpotifyPlaylists?
    public let tracks: SpotifyTracks?
}
