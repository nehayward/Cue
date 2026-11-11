import Foundation
import MusicKit

public final class AppleMusicAPI {
    public static var shared = AppleMusicAPI()
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied
    private let decoder: JSONDecoder
    private var storeFront: String?

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }
    
    /// Updates the favorite status of a song in Apple Music
    /// - Parameters:
    ///   - songId: The ID of the song to update
    ///   - favorite: If true, marks the song as favorite. If false, removes favorite status
    /// - Throws: Error if the API request fails or if the song cannot be found
    public func updateFavoriteStatus(songId: String, favorite: Bool) async throws {
        // Resolve to catalog ID if this is a library song
        let catalogId: String
        if songId.hasPrefix("i") {
            guard let catalogSong = try? await librarySongCatalog(id: songId),
                  let song = catalogSong.data.first else {
                return
            }
            catalogId = song.id
        } else {
            catalogId = songId
        }

        if favorite {
            // Add song to library so it appears in Favorite Songs playlist
            let libraryURL = URL(string: "https://api.music.apple.com/v1/me/library?ids[songs]=\(catalogId)")!
            var libraryRequest = URLRequest(url: libraryURL)
            libraryRequest.httpMethod = "POST"
            _ = try? await MusicDataRequest(urlRequest: libraryRequest).response()

            // Rate as favorite
            let ratingURL = URL(string: "https://api.music.apple.com/v1/me/ratings/songs/\(catalogId)")!
            var ratingRequest = URLRequest(url: ratingURL)
            ratingRequest.httpMethod = "PUT"
            let body: [String: Any] = [
                "attributes": [
                    "value": 1
                ],
                "type": "ratings"
            ]
            ratingRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try? await MusicDataRequest(urlRequest: ratingRequest).response()
        } else {
            // Remove favorite rating
            let ratingURL = URL(string: "https://api.music.apple.com/v1/me/ratings/songs/\(catalogId)")!
            var ratingRequest = URLRequest(url: ratingURL)
            ratingRequest.httpMethod = "DELETE"
            _ = try? await MusicDataRequest(urlRequest: ratingRequest).response()
        }
    }
    
    /// The ratings path for an album: a library album's id (`l.…`) is only
    /// known to the library's ratings, a catalog album's to the catalog's.
    private func albumRatingsPath(_ albumId: String) -> String {
        albumId.hasPrefix("l.") ? "library-albums" : "albums"
    }

    public func updateAlbumFavoriteStatus(albumId: String, favorite: Bool) async throws {
        let ratingURL = URL(string: "https://api.music.apple.com/v1/me/ratings/\(albumRatingsPath(albumId))/\(albumId)")!
        var ratingRequest = URLRequest(url: ratingURL)
        if favorite {
            ratingRequest.httpMethod = "PUT"
            let body: [String: Any] = ["attributes": ["value": 1], "type": "ratings"]
            ratingRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            ratingRequest.httpMethod = "DELETE"
        }
        // A library album is in the library already.
        if favorite, !albumId.hasPrefix("l.") {
            let libraryURL = URL(string: "https://api.music.apple.com/v1/me/library?ids[albums]=\(albumId)")!
            var libraryRequest = URLRequest(url: libraryURL)
            libraryRequest.httpMethod = "POST"
            _ = try? await MusicDataRequest(urlRequest: libraryRequest).response()
        }
        _ = try? await MusicDataRequest(urlRequest: ratingRequest).response()
    }

    public func isAlbumFavorite(albumId: String) async throws -> Bool {
        let url = URL(string: "https://api.music.apple.com/v1/me/ratings/\(albumRatingsPath(albumId))?ids=\(albumId)")!
        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        guard let response = try? await request.response() else { return false }
        struct RatingResponse: Codable { let data: [RatingItem] }
        struct RatingItem: Codable { let id: String }
        if let ratingResponse = try? decoder.decode(RatingResponse.self, from: response.data) {
            return !ratingResponse.data.isEmpty
        }
        return false
    }

    public func isFavorite(songId: String) async throws -> Bool {
        let catalogId: String
        if songId.hasPrefix("i") {
            guard let catalogSong = try? await librarySongCatalog(id: songId), let song = catalogSong.data.first else { return false }
            catalogId = song.id
        } else {
            catalogId = songId
        }
        let addToPlaylistURL = URL(string: "https://api.music.apple.com/v1/me/ratings/songs?ids=\(catalogId)")!
        let urlRequest = URLRequest(url: addToPlaylistURL)
        let request = MusicDataRequest(urlRequest: urlRequest)
        guard let response = try? await request.response() else { return false }
        
        struct Rating: Codable {
            let id: String
            let type: String
            let href: String
            let attributes: RatingAttributes
        }
        
        struct RatingAttributes: Codable {
            let value: Int
        }
        
        struct RatingResponse: Codable {
            let data: [Rating]
        }
        
        if let ratingResponse = try? decoder.decode(RatingResponse.self, from: response.data) {
            return !ratingResponse.data.isEmpty
        }
        return false
    }
    
    /// Adds a song to a user library playlist.
    /// - Parameters:
    ///   - songId: The identifier of the song.
    ///   - type: The Apple Music resource type — `"songs"` for catalog tracks, `"library-songs"` for items already in the user's library.
    ///   - playlistID: The library playlist identifier.
    @discardableResult
    public func addSongToPlaylist(songId: String, type: String = "songs", playlistID: String) async throws -> Bool {
        let tracksURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks")!
        var urlRequest = URLRequest(url: tracksURL)

        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "data": [
                [
                    "id": songId,
                    "type": type
                ]
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let request = MusicDataRequest(urlRequest: urlRequest)
        guard let response = try? await request.response() else {
            return false
        }
        // Apple Music returns 2xx (typically 201) on success.
        return (200..<300).contains(response.urlResponse.statusCode)
    }

    /// Creates a new playlist in the user's library and returns its identifier.
    public func createLibraryPlaylist(name: String, description: String? = nil) async throws -> String? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists")!
        var urlRequest = URLRequest(url: playlistsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var attributes: [String: Any] = ["name": name]
        if let description { attributes["description"] = description }
        let body: [String: Any] = ["attributes": attributes]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let request = MusicDataRequest(urlRequest: urlRequest)
        guard let response = try? await request.response() else { return nil }
        guard let container = try? decoder.decode(AppleLibraryContainer.self, from: response.data) else { return nil }
        return container.data.first?.id
    }
    
    public func getUserPlaylist(with id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        guard let urlComponents = URLComponents(string: "https://api.music.apple.com/v1/me/library/playlists/\(id)"), let url = urlComponents.url else { return nil }
        let request = MusicDataRequest(urlRequest: .init(url: url))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }
        
    public func getUserPlaylists(offset: Int = 0, limit: Int? = nil) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        var urlComponents = URLComponents(string: "https://api.music.apple.com/v1/me/library/playlists")!
        // Each saying whether it's a favorite, for the star on its tile.
        var queryItems = [URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "extend", value: "inFavorites")]
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        urlComponents.queryItems = queryItems
        
        let request = MusicDataRequest(urlRequest: .init(url: urlComponents.url!))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            print(appleUserPlaylistContainer.data.count)
            return appleUserPlaylistContainer
        } catch {
            print(error)
            print(String(decoding: response!.data, as: UTF8.self))
            return nil
        }
    }
    
    public func getUserPlaylistsFolders(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/playlist-folders?offset=\(offset)")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        print(String(decoding: data, as: UTF8.self))
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            print(error)
            print(String(decoding: response!.data, as: UTF8.self))
            return nil
        }
    }
    
    public func getPlaylistFolder(id: String, offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let folderURL = URL(string: "https://api.music.apple.com/v1/me/library/playlist-folders/\(id)/children?offset=\(offset)")!
        let request = MusicDataRequest(urlRequest: .init(url: folderURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            print(error)
            print(String(decoding: response!.data, as: UTF8.self))
            return nil
        }
    }

    /// A page of the person's library from the web API, alphabetical, each
    /// item saying whether it's a favorite (`inFavorites`, `extend`ed:
    /// library items leave it out otherwise).
    ///
    /// `favoritesOnly` has Apple leave out everything else
    /// (`filter[inFavorites]=true`). The reference lists `inFavorites` as an
    /// attribute but not the filter; checked against a real library on
    /// 2026-11-10 for albums, songs, artists and playlists: it gives only the
    /// favorites, pages with `next` as usual and has no `meta.total`, and
    /// `=false` is an error rather than "all but the favorites".
    ///
    /// Artists and songs include their catalog item: a library artist has
    /// no artwork of its own, and a library song no preview. Nil when the
    /// read failed, so a caller can tell that from an empty list.
    public func getLibrary(_ resource: AppleLibraryResource, offset: Int = 0, limit: Int = 100, favoritesOnly: Bool = false) async -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        var components = URLComponents(string: "https://api.music.apple.com/v1/me/library/\(resource.rawValue)")!
        var queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "extend", value: "inFavorites"),
        ]
        if favoritesOnly {
            queryItems.append(URLQueryItem(name: "filter[inFavorites]", value: "true"))
        }
        if resource == .artists || resource == .songs {
            queryItems.append(URLQueryItem(name: "include", value: "catalog"))
        }
        components.queryItems = queryItems
        guard let url = components.url,
              let response = try? await MusicDataRequest(urlRequest: URLRequest(url: url)).response() else { return nil }
        return try? decoder.decode(AppleLibraryContainer.self, from: response.data)
    }

    /// A page of a library playlist's tracks, each saying whether it's a
    /// favorite, as `getLibrary`'s songs.
    public func getLibraryPlaylistTracks(id: String, offset: Int = 0, limit: Int = 100) async -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        var components = URLComponents(string: "https://api.music.apple.com/v1/me/library/playlists/\(id)/tracks")!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "extend", value: "inFavorites"),
            URLQueryItem(name: "include", value: "catalog"),
        ]
        guard let url = components.url,
              let response = try? await MusicDataRequest(urlRequest: URLRequest(url: url)).response() else { return nil }
        return try? decoder.decode(AppleLibraryContainer.self, from: response.data)
    }

    /// A page of the user's library albums in the requested order, from
    /// MusicKit's index of the library rather than the web API: the web
    /// API's `/me/library/albums` takes no sort, so an order other than its
    /// own would mean fetching the whole library first.
    public func libraryAlbums(
        sort: AppleLibrarySort = .title,
        descending: Bool = false,
        offset: Int = 0,
        limit: Int = 100
    ) async throws -> [Album] {
        guard await requestMusicAuthorization() else { return [] }

        var request = MusicLibraryRequest<Album>()
        switch sort {
        case .title, .album:
            request.sort(by: \.title, ascending: !descending)
        case .artist:
            request.sort(by: \.artistName, ascending: !descending)
        case .releaseDate:
            request.sort(by: \.releaseDate, ascending: !descending)
        case .dateAdded:
            request.sort(by: \.libraryAddedDate, ascending: !descending)
        }
        request.limit = limit
        request.offset = offset
        let response = try await request.response()
        return Array(response.items)
    }

    /// A page of the library's songs in the requested order, from MusicKit's
    /// index of the library, as `libraryAlbums(sort:)`. Its ids are the
    /// device's own, the ones `ApplicationMusicPlayer` plays (a downloaded
    /// copy offline too). MusicKit doesn't sort songs by release date
    /// (`librarySongReleaseDates` is for that); asked for it, this gives
    /// them by title.
    public func librarySongs(
        sort: AppleLibrarySort = .title,
        descending: Bool = false,
        offset: Int = 0,
        limit: Int = 100
    ) async throws -> [Song] {
        guard await requestMusicAuthorization() else { return [] }

        var request = MusicLibraryRequest<Song>()
        switch sort {
        case .title, .releaseDate, .dateAdded:
            request.sort(by: \.title, ascending: !descending)
        case .artist:
            request.sort(by: \.artistName, ascending: !descending)
        case .album:
            request.sort(by: \.albumTitle, ascending: !descending)
        }
        request.limit = limit
        request.offset = offset
        let response = try await request.response()
        return Array(response.items)
    }

    /// Every library song's id and release date, in title order, for the
    /// one song order MusicKit can't give. Read a thousand at a time and
    /// kept as just those two, not the songs: ten thousand `Song`s are a
    /// lot to hold for a sort. Nil when a read failed.
    public func librarySongReleaseDates() async -> [(id: String, released: Date?)]? {
        guard await requestMusicAuthorization() else { return nil }

        var dates: [(id: String, released: Date?)] = []
        let pageSize = 1000
        while !Task.isCancelled {
            var request = MusicLibraryRequest<Song>()
            request.sort(by: \.title, ascending: true)
            request.limit = pageSize
            request.offset = dates.count
            guard let page = try? await request.response().items else { return nil }
            dates += page.map { (id: $0.id.rawValue, released: $0.releaseDate) }
            guard page.count == pageSize else { return dates }
        }
        return nil
    }

    /// Library songs by MusicKit id, in the order asked for; an id MusicKit
    /// doesn't have is left out.
    public func librarySongs(ids: [String]) async -> [Song] {
        guard !ids.isEmpty, await requestMusicAuthorization() else { return [] }
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, memberOf: ids.map { MusicItemID($0) })
        request.limit = ids.count
        guard let songs = try? await request.response().items else { return [] }
        let byID = Dictionary(songs.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// The web API's rows for library albums by id, in chunks. The rows
    /// `libraryAlbums(sort:)` returns carry `musickit://` artwork that only
    /// MusicKit's own views can draw; the web API's rows for the same
    /// albums carry ordinary https artwork, so a sorted page is drawn from
    /// these. Order is not preserved — callers match rows up by id.
    public func libraryAlbums(ids: [String]) async throws -> [AppleLibraryItem] {
        guard !ids.isEmpty, await requestMusicAuthorization() else { return [] }

        // The library endpoints take fewer ids per request than the catalog's
        // hundred; 25 is what the web API's own client sends.
        let chunks = stride(from: 0, to: ids.count, by: 25).map { Array(ids[$0..<min($0 + 25, ids.count)]) }
        return await withTaskGroup(of: [AppleLibraryItem].self) { group in
            for chunk in chunks {
                group.addTask { [decoder] in
                    guard let url = URL(string: "https://api.music.apple.com/v1/me/library/albums?ids=\(chunk.joined(separator: ","))"),
                          let response = try? await MusicDataRequest(urlRequest: .init(url: url)).response(),
                          let container = try? decoder.decode(AppleLibraryContainer.self, from: response.data)
                    else { return [] }
                    return container.data
                }
            }
            var items: [AppleLibraryItem] = []
            for await chunk in group {
                items.append(contentsOf: chunk)
            }
            return items
        }
    }

    public func lookupUsersPlaylist(id: String) async throws -> Playlist? {
        guard await requestMusicAuthorization() else { return nil }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        return response.items.first
    }

    public func lookupUsersLibraryPlaylist(id: String, offset: Int) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(id)/tracks?offset=\(offset)&include=catalog")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }

    public func lookupUsersLibraryAlbum(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/albums/\(id)/tracks?include=catalog")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }

    public func userLibraryAlbum(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/albums/\(id)")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }

    public func lookupUsersRecentPlayed(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/recent/played?offset=\(offset)")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }

    public func lookupUsersRecentAddedTracks(offset: Int = 0, limit: Int? = nil) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/recently-added?offset=\(offset)&limit=\(limit ?? 25)")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let recentlyAddedTracks = try decoder.decode(AppleLibraryContainer.self, from: data)
            return recentlyAddedTracks
        } catch {
            return nil
        }
    }
    
    public func lookupUsersRecentRadioStations(offset: Int = 0, limit: Int? = nil) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let radioStationsURL = URL(string: "https://api.music.apple.com/v1/me/recent/radio-stations?offset=\(offset)&limit=\(limit ?? 25)")!
        let request = MusicDataRequest(urlRequest: .init(url: radioStationsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let recentRadioStations = try decoder.decode(AppleLibraryContainer.self, from: data)
            return recentRadioStations
        } catch {
            print("Error decoding radio stations: \(error)")
            return nil
        }
    }
    
    public func lookupAppleRadioStations(offset: Int = 0, limit: Int? = nil) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let region = (Locale.current.region?.identifier ?? "US").lowercased()
        let radioStationsURL = URL(string: "https://api.music.apple.com/v1/catalog/\(region)/stations?filter[identity]=personal&offset=\(offset)&limit=\(limit ?? 25)")!
        let request = MusicDataRequest(urlRequest: .init(url: radioStationsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        do {
            let radioStations = try decoder.decode(AppleLibraryContainer.self, from: data)
            return radioStations
        } catch {
            print(error)
            return nil
        }
    }

    /// Apple's own live stations — Apple Music 1, Hits, Country, and the
    /// rest of the broadcast lineup — as opposed to the user's personal ones.
    public func lookupAppleLiveRadioStations(limit: Int = 25) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let region = (Locale.current.region?.identifier ?? "US").lowercased()
        let stationsURL = URL(string: "https://api.music.apple.com/v1/catalog/\(region)/stations?filter[featured]=apple-music-live-radio&limit=\(limit)")!
        let request = MusicDataRequest(urlRequest: .init(url: stationsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        do {
            return try decoder.decode(AppleLibraryContainer.self, from: data)
        } catch {
            print("Error decoding live radio stations: \(error)")
            return nil
        }
    }

    public func searchRadioStations(term: String, limit: Int = 10) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        let region = (Locale.current.region?.identifier ?? "US").lowercased()
        let searchURL = URL(string: "https://api.music.apple.com/v1/catalog/\(region)/search?term=\(encodedTerm)&types=stations&limit=\(limit)")!
        let request = MusicDataRequest(urlRequest: .init(url: searchURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let searchResponse = try decoder.decode(AppleRadioSearchResponse.self, from: data)
            guard let stations = searchResponse.results.stations else { return nil }
            return AppleLibraryContainer(data: stations.data, meta: nil, next: stations.next)
        } catch {
            print("Error decoding radio search: \(error)")
            return nil
        }
    }
    
    public func lookupUsersNew(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/for-you?offset=\(offset)&limit=25")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let recentlyAddedTracks = try decoder.decode(AppleLibraryContainer.self, from: data)
            return recentlyAddedTracks
        } catch {
            return nil
        }
    }
    
    public func lookupUsersStations(offset: Int = 0) async throws -> AppleLibraryContainer? {
//        guard await requestMusicAuthorization() else { return nil }
//
//        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/for-you?offset=\(offset)&limit=25")!
//        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
//        let response = try? await request.response()
//        guard let data = response?.data else { return nil }
//
//        do {
//            let recentlyAddedTracks = try decoder.decode(AppleLibraryContainer.self, from: data)
//            return recentlyAddedTracks
//        } catch {
//            return nil
//        }
        return nil
    }

    public func getUserRecommendations(offset: Int = 0, limit: Int = 25) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        var urlComponents = URLComponents(string: "https://api.music.apple.com/v1/me/recommendations")!
        var queryItems = [
            URLQueryItem(name: "include", value: "albums"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        // Add localization if available
        if let languageCode = Locale.current.language.languageCode?.identifier,
           let regionCode = Locale.current.region?.identifier {
            queryItems.append(URLQueryItem(name: "l", value: "\(languageCode)-\(regionCode)"))
        }
        
        urlComponents.queryItems = queryItems
        
        let request = MusicDataRequest(urlRequest: .init(url: urlComponents.url!))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let recommendationsResponse = try decoder.decode(AppleRecommendationsResponse.self, from: data)
            
            // Filter and collect all album items from all recommendations
            var albumItems: [AppleLibraryItem] = []
            
            for recommendation in recommendationsResponse.data {
                let albums = recommendation.relationships.contents.data.filter { $0.type == "albums" }
                albumItems.append(contentsOf: albums)
            }
            
            // Create a container with the filtered album items
            return AppleLibraryContainer(
                data: albumItems,
                meta: nil,
                next: recommendationsResponse.next
            )
        } catch {
            print("Error decoding user recommendations: \(error)")
            print("Response data: \(String(decoding: data, as: UTF8.self))")
            return nil
        }
    }

    public func librarySong(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let librarySongURL = URL(string: "https://api.music.apple.com/v1/me/library/songs/\(id)")!
        let request = MusicDataRequest(urlRequest: .init(url: librarySongURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }
    
    public func catalogSong(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let librarySongURL = URL(string: "https://api.music.apple.com/v1/catalog/us/songs/\(id)")!
        let request = MusicDataRequest(urlRequest: .init(url: librarySongURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }
        print(String(decoding: data, as: UTF8.self))
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }

    public func librarySongCatalog(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let librarySongURL = URL(string: "https://api.music.apple.com/v1/me/library/songs/\(id)/catalog")!
        let request = MusicDataRequest(urlRequest: .init(url: librarySongURL))
        let response = try? await request.response()
//        print(String(decoding: response!.data, as: UTF8.self))
        guard let data = response?.data else { return nil }

        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            return nil
        }
    }

    public func libraryAlbumFromTrack(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let librarySongURL = URL(string: "https://api.music.apple.com/v1/me/library/songs/\(id)/catalog")!
        let request = MusicDataRequest(urlRequest: .init(url: librarySongURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            guard let id = appleUserPlaylistContainer.data.first?.id else { return nil }
            let album = URL(string: "https://api.music.apple.com/v1/catalog/songs/\(id)/albums")!
            let request = MusicDataRequest(urlRequest: .init(url: album))
            let response = try? await request.response()
            guard let data = response?.data else { return nil }
            let albumContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return albumContainer
        } catch {
            return nil
        }
    }
    
    public func libraryArtistLookup(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let artistURL = URL(string: "https://api.music.apple.com/v1/me/library/artists/\(id)/catalog")!
        let request = MusicDataRequest(urlRequest: .init(url: artistURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let libraryContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return libraryContainer
        } catch {
            print(error)
            return nil
        }
    }
    
    public func libraryArtistArtwork(artistName: String) async throws -> URL? {
        guard await requestMusicAuthorization() else { return nil }
        let request = MusicLibraryRequest<Artist>()
        let response = try await request.response()

        if let artist = response.items.first(where: { $0.name.lowercased() == artistName.lowercased() }) {
            if let artwork = artist.artwork {
                return artwork.url(width: 300, height: 300)
            } else {
                print("No artwork found for this artist")
            }
        } else {
            print("Artist not found in the user's library")
        }
        return nil
    }
    
    public func artistArtwork(for name: String, size: Int = 100) async -> URL? {
        guard await requestMusicAuthorization() else { return nil }
        return await Self.artistArtworkLookups.url(for: "\(name)|\(size)") {
            var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
            request.includeTopResults = true
            request.limit = 2
            guard let results = try? await request.response() else { return nil }
            return results.artists.first?.artwork?.url(width: size, height: size)
        }
    }

    /// Artist pictures found by name, kept for the session. A library artist
    /// row with no picture of its own searched the catalog for one each
    /// time it appeared — scrolling back over a list repeated the lot.
    private static let artistArtworkLookups = ArtistArtworkLookups()
    
    public func libraryArtistAlbums(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let artistURL = URL(string: "https://api.music.apple.com/v1/me/library/artists/\(id)/albums")!
        let request = MusicDataRequest(urlRequest: .init(url: artistURL))
        let response = try? await request.response()
        guard let data = response?.data else { return nil }

        do {
            let libraryContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return libraryContainer
        } catch {
            print(error)
            return nil
        }
    }
    
    /// The library's songs credited to `artistName`, up to `limit`. A library
    /// artist has no songs relationship, and one whose songs all sit on other
    /// artists' albums (a soundtrack, a feature, songs saved from a playlist)
    /// has no albums either, so they're found by searching the library.
    public func librarySongs(byArtist artistName: String, limit: Int = 50) async -> [AppleLibraryItem] {
        guard await requestMusicAuthorization() else { return [] }

        let pageSize = 25
        var matches: [AppleLibraryItem] = []
        var offset = 0
        while offset < 200 {
            var components = URLComponents(string: "https://api.music.apple.com/v1/me/library/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: artistName),
                URLQueryItem(name: "types", value: "library-songs"),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
            ]
            guard let url = components.url,
                  let data = try? await MusicDataRequest(urlRequest: .init(url: url)).response().data,
                  let page = try? decoder.decode(AppleLibrarySearchContainer.self, from: data).results.librarySongs?.data,
                  !page.isEmpty else { break }
            matches += page
            guard page.count == pageSize else { break }
            offset += pageSize
        }

        // The term also matches titles and albums. Songs credited to the
        // artist alone, else ones they share ("Noah Kahan & Hozier").
        let solo = matches.filter { $0.attributes.artistName?.localizedCaseInsensitiveCompare(artistName) == .orderedSame }
        let songs = solo.isEmpty
            ? matches.filter { $0.attributes.artistName?.localizedCaseInsensitiveContains(artistName) ?? false }
            : solo
        return Array(songs.prefix(limit))
    }

    public func librarySearch(term: String, types: String = "library-albums,library-artists,library-playlists,library-songs") async throws -> AppleLibrarySearchContainer? {
        guard await requestMusicAuthorization() else { return nil }

        // Encoded as a query item: a title with an "&" or a "#" in it cut
        // the address short.
        var components = URLComponents(string: "https://api.music.apple.com/v1/me/library/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "types", value: types),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let librarySongURL = components.url else { return nil }
        let request = MusicDataRequest(urlRequest: .init(url: librarySongURL))
        let response = try? await request.response()
        
        guard let data = response?.data else { return nil }
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibrarySearchContainer.self, from: data)
            return appleUserPlaylistContainer
        } catch {
            print(error)
            return nil
        }
    }
    // MARK: TODO
//    /// Possible types: Heavy rotation, recently added, and recently played resources.
//    public enum MusicHistoryEndpoints {
//      case heavyRotation
//      case recentlyAdded
//      case recentlyPlayed
//      case recentlyPlayedTracks
//      case recentlyPlayedStations
//
//      var path: String {
//        switch self {
//          case .heavyRotation:
//            return "history/heavy-rotation"
//          case .recentlyAdded:
//            return "library/recently-added"
//          case .recentlyPlayed:
//            return "recent/played"
//          case .recentlyPlayedTracks:
//            return "recent/played/tracks"
//          case .recentlyPlayedStations:
//            return "recent/radio-stations"
//        }
//      }

    /// Fetches full MusicKit `Song`s for Apple Music catalog song ids. Sonos
    /// playback only needs the id baked into a URI, but local on-device
    /// playback queues `Song` values into `ApplicationMusicPlayer`, so this is
    /// the path that turns a search result back into something playable here.
    public func songs(ids: [String]) async throws -> [Song] {
        guard await requestMusicAuthorization() else { return [] }
        // The catalog takes a limited number of ids per request, so a long
        // queue goes in several, side by side.
        let chunks = stride(from: 0, to: ids.count, by: 100).map { Array(ids[$0..<min($0 + 100, ids.count)]) }
        return try await withThrowingTaskGroup(of: [Song].self) { group in
            for chunk in chunks {
                group.addTask {
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
                    return Array(try await request.response().items)
                }
            }
            var songs: [Song] = []
            for try await page in group {
                songs += page
            }
            return songs
        }
    }

    public func requestMusicAuthorization() async -> Bool {
        let status = await AppleMusicPermission.request()

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


/// Lookups by key, each made once: a second caller waits on the first
/// one's answer, and an answer of none is remembered too.
private actor ArtistArtworkLookups {
    private var lookups: [String: Task<URL?, Never>] = [:]

    func url(for key: String, lookUp: @escaping @Sendable () async -> URL?) async -> URL? {
        if let lookup = lookups[key] { return await lookup.value }
        if lookups.count >= 1000 { lookups.removeAll() }
        let lookup = Task { await lookUp() }
        lookups[key] = lookup
        return await lookup.value
    }
}
