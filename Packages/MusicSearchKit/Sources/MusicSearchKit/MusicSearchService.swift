import Foundation
import MusicKit

@Observable
public final class MusicSearchService {
    public static var shared = MusicSearchService()

    public var query: String = "" {
        didSet {
            if _query.isEmpty {
                suggestions.removeAll()
                topResults = []
            }
        }
    }
    
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied
    private let appleMusicSearchAPI = AppleMusicSearchAPI()
    private let spotifySearchAPI = SpotifyAPI()
    private var searchSuggestionTask = Task<([MusicCatalogSearchSuggestionsResponse.Suggestion], MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult>)?, Never> { nil }
    private var spotifySearchTask = Task<(SpotifyResult)?, Never> { nil }

    private let debounceDuration: Duration = .milliseconds(200)

    public var suggestions: [MusicCatalogSearchSuggestionsResponse.Suggestion] = []
    public var topResults:  MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult> = []
    public var spotifyResult: SpotifyResult?
    public var newReleases: [SpotifyAlbumItem] = []

    public init() { }

    public func search(for provider: MediaSearchService) async {
        if query.isEmpty { return }

        // Cancel the previous task if it exists
        searchSuggestionTask.cancel()
        spotifySearchTask.cancel()

        // Create a new task
        searchSuggestionTask = Task { [weak self] in
            // Delay execution to debounce
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            let results = await searchSuggestion(query: query)
            return results
        }

        // Create a new task
        spotifySearchTask = Task { [weak self] in
            // Delay execution to debounce
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            let results = await searchSpotify(query: query)
            return results
        }

        // Wait for the task to complete and return the result
        guard let results = await searchSuggestionTask.value else { return }
        suggestions = results.0

        switch provider {
        case .apple:
            topResults = results.1
        case .spotify:
            guard let result = await spotifySearchTask.value else { return }
            Task { @MainActor in
                spotifyResult = result
            }
        }
    }

    public func searchSuggestion(query: String) async -> ([MusicCatalogSearchSuggestionsResponse.Suggestion],  
                                                          MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult>)? {
        if query.isEmpty { return ([], []) }
        guard await requestMusicAuthorization() else { return ([], []) }

        var request = MusicCatalogSearchSuggestionsRequest(term: query, includingTopResultsOfTypes: [Song.self, Album.self, Artist.self, Playlist.self])
//        var request = MusicCatalogSearchSuggestionsRequest(term: query, includingTopResultsOfTypes: [Song.self])
        request.limit = 10
        do {
            let response = try await request.response()
            return (response.suggestions, response.topResults)
        } catch {
            print(error)
            return nil
        }
    }

//    public func search(query: String, service: MusicSearchService) -> [MediaContent] {
//
//
//        return []
//    }

    public func search(song: String, artist: String) async -> [ItunesResult] {
        await appleMusicSearchAPI.search(for: "\(song) \(artist)")
    }

    public func appleLookup(id: String) async -> ItunesResult? {
        await appleMusicSearchAPI.lookupTrack(id: id)
    }

    public func spotifyNewReleases() async -> SpotifyResult? {
        await spotifySearchAPI.newReleases()
    }

    public func searchSpotify(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.search(for: "\(song) \(artist)", types: [.playlist])
    }

    public func searchSpotifySong(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.searchSong(for: "\(song) \(artist)")
    }

    public func spotifyTrackLookup(id: String) async -> SpotifyTrackItem? {
        await spotifySearchAPI.lookupTrack(id: id)
    }

    public func spotifyPlaylistLookup(id: String) async -> SpotifyPlaylistItems? {
        await spotifySearchAPI.playlist(id: id)
    }

    public func spotifyAlbumLookup(id: String) async -> SpotifyAlbumItem? {
        await spotifySearchAPI.album(id: id)
    }

    public func spotifyAlbumTracksLookup(id: String) async -> SpotifyAlbumDetails? {
        await spotifySearchAPI.albumDetails(id: id)
    }

    public func spotifyPlaylist(id: String) async -> SpotifyPlaylistItems? {
        await spotifySearchAPI.playlist(id: id)
    }

    public func spotifyArtist(id: String) async -> SpotifyArtistsItems? {
        await spotifySearchAPI.artist(id: id)
    }

    public func spotifyArtistAlbums(id: String) async -> SpotifyArtistAlbums? {
        await spotifySearchAPI.artistAlbums(id: id)
    }

    public func spotifyArtistTopTracks(id: String) async -> [SpotifyTrackItem] {
        await spotifySearchAPI.artistTopTracks(id: id)
    }

    public func searchSpotify(query: String) async -> SpotifyResult? {
        await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track])
    }

//    public func searchSpotifyTopResults(query: String) async -> [String] {
//        let results = await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track])
//
////        let top = results?.playlists?.items.sorted(by: { a, b in
////            a.popularity < b.popularity
////        }).map({ item in
////            return "\(item.name).\(item.popularity)"
////        })
//
//        print(results)
//
//        return []
//    }

    public func searchAppleMusic(query: String) async -> String {
        guard await requestMusicAuthorization() else { return "" }

        var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self])
        request.includeTopResults = true
        let response = try? await request.response()
        print(response)

//        guard let song = response.songs.first else { return  "" }
//
//        print(song.title)
//        print(song.isrc)
//        var catalogResource = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: song.id)
//        let response2 = try await request.response()
//        print(response2)
//        let request =  MusicCatalogSearchRequest(term: "wekend", types: [Album.self])
//
//        print(searchResponse)
//
//        print(searchResponse.songs)
//        print(searchResponse.artists)
        return ""
    }

    public func lookup(id: String) async throws -> Song? {
        guard await requestMusicAuthorization() else { return nil }
        let musicItemID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: musicItemID)
        catalogResource.properties = [.albums, .artists]
        let response = try await catalogResource.response()
        return response.items.first
    }

    public func lookup(id: String) async throws -> Album? {
        guard await requestMusicAuthorization() else { return nil }

        let albumID = MusicItemID(id)
        print(id)
        var catalogResource = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.tracks, .artists]
        let response2 = try await catalogResource.response()
        print(response2)
//        let request =  MusicCatalogSearchRequest(term: "wekend", types: [Album.self])
//
//        print(searchResponse)
//
//        print(searchResponse.songs)
//        print(searchResponse.artists)
        return response2.items.first
    }

    public func lookup(id: String) async throws -> Playlist? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: playlistID)
        catalogResource.properties = [.tracks]
        let response = try await catalogResource.response()
        return response.items.first
    }

    public func lookup(id: String) async throws -> Artist? {
        guard await requestMusicAuthorization() else { return nil }

        let albumID = MusicItemID(id)
        print(id)
        var catalogResource = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.albums, .topSongs]
        let response = try await catalogResource.response()
        print(response)
//        let request =  MusicCatalogSearchRequest(term: "wekend", types: [Album.self])
//
//        print(searchResponse)
//
//        print(searchResponse.songs)
//        print(searchResponse.artists)
        return response.items.first
    }

//    public func myPlaylists() async throws -> [Playlist]? {
//        guard await requestMusicAuthorization() else { return nil }
//        var request = MusicLibraryRequest<Playlist>()
//        request.sort(by: \.lastPlayedDate, ascending: false)
//        let response = try await request.response()
//        return response.items
//    }


    public func requestMusicAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()

        switch status {
        case .notDetermined:
            appleMusicAuthorizationStatus = .notDetermined
        case .denied, .restricted:
            appleMusicAuthorizationStatus = .denied
        case .authorized:
            appleMusicAuthorizationStatus = .authorized
            return true
        default:
            appleMusicAuthorizationStatus = .denied
        }
        return false
    }

    public func getMusicAuthorization() -> AppleMusicAuthorization {
        let status = MusicAuthorization.currentStatus

        switch status {
        case .notDetermined:
            appleMusicAuthorizationStatus = .notDetermined
        case .denied, .restricted:
            appleMusicAuthorizationStatus = .denied
        case .authorized:
            appleMusicAuthorizationStatus = .authorized
        default:
            appleMusicAuthorizationStatus = .denied
        }
        return appleMusicAuthorizationStatus
    }
}



