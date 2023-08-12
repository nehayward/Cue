import Foundation

public final class MusicSearchService {
    private let appleMusicSearchAPI = AppleMusicSearchAPI()
    private let spotifySearchAPI = SpotifySearchAPI()

    public init() {

    }
    
    public func search(song: String, artist: String) async -> [ItunesResult] {
        await appleMusicSearchAPI.search(for: "\(song) \(artist)")
    }


    public func searchSpotify(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.search(for: "\(song) \(artist)")
    }

    public func searchSpotifySong(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.searchSong(for: "\(song) \(artist)")
    }
}



