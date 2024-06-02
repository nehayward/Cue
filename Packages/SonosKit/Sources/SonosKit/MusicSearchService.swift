import Foundation
import MusicKit
import MusicSearchKit

@Observable
public final class MusicSearchService {
    public static var shared = MusicSearchService()

    public var query: String = "" {
        didSet {
            if _query.isEmpty {
                suggestions.removeAll()
            }
        }
    }
    
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied
    public var plexAuthorization: AppleMusicAuthorization = .denied

    private let appleMusicSearchAPI = AppleMusicSearchAPI()
    private let apple = AppleMusicAPI()
    private let plex = PlexAPI()
    private let tidal = TidalAPI()
    private let spotifySearchAPI = SpotifyAPI()
    private let sonosService = SonosService.shared

    private var searchSuggestionTask = Task<([MusicCatalogSearchSuggestionsResponse.Suggestion], MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult>)?, Never> { nil }
    private var appleSearchTask = Task<([PlayableContent])?, Never> { nil }
    private var spotifySearchTask = Task<([PlayableContent])?, Never> { nil }
    private var librarySearchTask = Task<([PlayableContent])?, Never> { nil }
    private var tidalSearchTask = Task<([PlayableContent])?, Never> { nil }
    private var plexSearchTask = Task<([PlayableContent])?, Never> { nil }

    private let debounceDuration: Duration = .milliseconds(200)

    public var suggestions: [MusicCatalogSearchSuggestionsResponse.Suggestion] = []

    public var appleResults: [PlayableContent] = []
    public var spotifyResults: [PlayableContent] = []
    public var librarySearchResults: [PlayableContent] = []
    public var plexResults: [PlayableContent] = []
    public var tidalResults: [PlayableContent] = []

    public var newReleases: [SpotifyAlbumItem] = []

    public init() { }

    public func search(for provider: MediaSearchService) async {
        if query.isEmpty { return }

        // Cancel the previous task if it exists
        searchSuggestionTask.cancel()
        spotifySearchTask.cancel()
        librarySearchTask.cancel()
        plexSearchTask.cancel()
        tidalSearchTask.cancel()

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
        appleSearchTask = Task { [weak self] in
            // Delay execution to debounce
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            let results = await searchAppleMusic(query: query)
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

        librarySearchTask = Task { [weak self] in
            // Delay execution to debounce
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            if provider == .library {
                let playableContent = await sonosService.librarySearch(query: query)
                return sortContentByMatchAndPopularity(playableContent: playableContent, query: query)
            }
            return nil
        }

        plexSearchTask = Task { [weak self] in
            // Delay execution to debounce
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            if provider == .plex {
                return await searchPlex(query: query)
            }
            return nil
        }

        tidalSearchTask = Task { [weak self] in
            // Delay execution to debounce
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            if provider == .tidal {
                return await searchTidal(query: query)
            }
            return nil
        }

        // Wait for the task to complete and return the result
        guard let results = await searchSuggestionTask.value else { return }
        suggestions = results.0

        switch provider {
        case .apple:
            guard let result = await appleSearchTask.value else { return }
            appleResults = result
        case .spotify:
            guard let result = await spotifySearchTask.value else { return }
            spotifyResults = result
        case .library:
            guard let librarySearchResults = await librarySearchTask.value else { return }
            self.librarySearchResults = librarySearchResults
        case .plex:
            guard let plexResults = await plexSearchTask.value else { return }
            self.plexResults = plexResults
        case .tidal:
            guard let tidalResults = await tidalSearchTask.value else { return }
            self.tidalResults = tidalResults
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

    public func search(song: String, artist: String, album: String) async -> [ItunesResult] {
        await appleMusicSearchAPI.search(for: "\(song) \(artist) \(album)")
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

    public func searchSpotify(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        guard let results = await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track]) else { return playableContent }

        if let tracks = results.tracks?.items {
            playableContent.append(contentsOf: tracks.map(\.toPlayable))
        }
        if let tracks = results.albums?.items {
            playableContent.append(contentsOf: tracks.map(\.toPlayable))
        }
        if let tracks = results.artists?.items {
            playableContent.append(contentsOf: tracks.map(\.toPlayable))
        }
        if let tracks = results.playlists?.items {
            playableContent.append(contentsOf: tracks.map(\.toPlayable))
        }

        return sortContentByMatchAndPopularity(playableContent: playableContent, query: query)
    }

    public func searchSpotifyPlayableContent(query: String) async -> [PlayableContent] {
        var playableContents: [PlayableContent] = []
        guard let results = await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track]) else { return [] }
        if let albums = results.albums?.items.map(\.toPlayable) {
            playableContents.append(contentsOf: albums)
        }

        return playableContents
    }

    public func searchAppleMusic(query: String) async -> [PlayableContent] {
        guard await requestMusicAuthorization() else { return [] }
        var playableContent: [PlayableContent] = []
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Playlist.self, Artist.self])
        request.includeTopResults = true
        request.limit = 20
        guard let results = try? await request.response() else { return [] }

        playableContent.append(contentsOf: results.songs.map(\.toPlayable))
        playableContent.append(contentsOf: results.albums.map(\.toPlayable))
        playableContent.append(contentsOf: results.artists.map(\.toPlayable))
        playableContent.append(contentsOf: results.playlists.map { $0.toPlayable(isUserPlaylist: true) })

        return sortContentByMatchAndPopularity(playableContent: playableContent, query: query)
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
        var catalogResource = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.tracks, .artists]
        let response2 = try await catalogResource.response()
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

    public func usersApplePlaylists() async -> [PlayableContent] {
        guard let playlists = try? await apple.getUserPlaylists() else { return [] }
        return playlists.map { $0.toPlayable(isUserPlaylist: true) }
    }

    public func tracksForUserPlaylists(id: String) async -> [PlayableContent] {
        guard let playlist = try? await apple.lookupUsersPlaylist(id: id) else { return [] }
        guard let tracks = try? await playlist.with([.tracks], preferredSource: .catalog).tracks else {
            return []
        }
        return tracks.map(\.toPlayableLibraryTrack)
    }

//    public func getTrackForApplePlaylists(id: String) async -> PlayableContent {
//        guard let playlists = try? await apple.lookupUsersPlaylist(id: id) else { return [] }
//        return playlists.map(\.toPlayable).first
//    }

//    public func myPlaylists() async throws -> [Playlist]? {
//        guard await requestMusicAuthorization() else { return nil }
//        var request = MusicLibraryRequest<Playlist>()
//        request.sort(by: \.lastPlayedDate, ascending: false)
//        let response = try await request.response()
//        return response.items
//    }

    // MARK: Tidal

    public func lookupTidalTrack(with id: String) async -> PlayableContent? {
        guard let song = await tidal.track(with: id) else { return nil }
        return song.toPlayable
    }

    public func lookupTidalAlbum(with id: String) async -> PlayableContent? {
        guard let album = await tidal.album(with: id) else { return nil }
        return album.toPlayable
    }

    public func lookupTidalAlbumTracks(id: String) async -> [PlayableContent] {
        let songs = await tidal.albumSongs(id: id)
        return songs.map { $0.toPlayable }
    }

    public func lookupTidalArtistTracks(id: String) async -> [PlayableContent] {
        let songs = await tidal.artistSongs(id: id)
        return songs.map { $0.toPlayable }
    }
    
    public func lookupTidalArtistAlbums(id: String) async -> [PlayableContent] {
        let songs = await tidal.artistAlbums(id: id)
        return songs.map { $0.toPlayable }
    }

    public func lookupTidalArtist(id: String) async -> PlayableContent? {
        guard let artist = await tidal.artist(with: id) else { return nil }
        return artist.toPlayable
    }

    private func searchPlex(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        guard let results = await plex.search(for: query) else { return playableContent }
        playableContent.append(contentsOf: results.tracks.map(\.toPlayable))
        playableContent.append(contentsOf: results.album.map(\.toPlayable))
        playableContent.append(contentsOf: results.artists.map(\.toPlayable))
        playableContent.append(contentsOf: results.playlists.map(\.toPlayable))

        return sortContentByMatchAndPopularity(playableContent: playableContent, query: query)
    }

    private func searchTidal(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        guard let results = await tidal.search(for: query) else { return playableContent }
        playableContent.append(contentsOf: results.tracks.map(\.resource.toPlayable))
        playableContent.append(contentsOf: results.albums.map(\.resource.toPlayable))
        playableContent.append(contentsOf: results.artists.map(\.resource.toPlayable))

        return sortContentByMatchAndPopularity(playableContent: playableContent, query: query)
    }

    func sortContentByMatchAndPopularity(playableContent: [PlayableContent], query: String) -> [PlayableContent] {
        return playableContent.sorted { item1, item2 in
            // Function to calculate a "fuzzy match score" based on how many characters in the query match characters in the title, in sequence
            func fuzzyMatchScore(source: String, query: String) -> Int {
                let lowerSource = source.lowercased()
                let lowerQuery = query.lowercased()
                var score = 0
                var index = lowerSource.startIndex

                // Increment score for each character in query that matches in sequence in the source
                for char in lowerQuery {
                    if let foundIndex = lowerSource[index...].firstIndex(of: char) {
                        score += 1
                        index = lowerSource.index(after: foundIndex) // Move index to right after the found character
                    }
                }

                return score
            }

            // Calculate match scores for both items
            let matchScore1 = fuzzyMatchScore(source: item1.title, query: query)
            let matchScore2 = fuzzyMatchScore(source: item2.title, query: query)

            // Primary sort by match score (descending)
            if matchScore1 != matchScore2 {
                return matchScore1 > matchScore2
            }

            // Secondary sort by popularity (descending); handle nil popularity by assigning a low default
            let popularity1 = item1.metadata?.popularity ?? -1
            let popularity2 = item2.metadata?.popularity ?? -1
            if popularity1 != popularity2 {
                return popularity1 > popularity2
            }

            // Tertiary sort by title (alphabetically)
            return item1.title.lowercased() < item2.title.lowercased()
        }
    }

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



