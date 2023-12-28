import Foundation

public final class MusicSearchService {
    private let appleMusicSearchAPI = AppleMusicSearchAPI()
    private let spotifySearchAPI = SpotifySearchAPI()

    public init() {

    }
    
    public func search(song: String, artist: String) async -> [ItunesResult] {
        await appleMusicSearchAPI.search(for: "\(song) \(artist)")
    }

    public func appleLookup(id: String) async -> ItunesResult? {
        await appleMusicSearchAPI.lookupTrack(id: id)
    }

    public func searchSpotify(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.search(for: "\(song) \(artist)", types: [.playlist])
    }

    public func searchSpotifySong(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.searchSong(for: "\(song) \(artist)")
    }

    public func spotifyTrackLookup(id: String) async -> SpotifyTrackItems? {
        await spotifySearchAPI.lookupTrack(id: id)
    }

    public func spotifyPlaylistLookup(id: String) async -> SpotifyPlaylistItems? {
        await spotifySearchAPI.playlist(id: id)
    }

    public func spotifyAlbumLookup(id: String) async -> SpotifyAlbumItems? {
        await spotifySearchAPI.album(id: id)
    }

    @MainActor
    public func searchSpotify(query: String) async -> SpotifyResult? {
        await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track])
    }
}



