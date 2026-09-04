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
    
    public func updateAlbumFavoriteStatus(albumId: String, favorite: Bool) async throws {
        let ratingURL = URL(string: "https://api.music.apple.com/v1/me/ratings/albums/\(albumId)")!
        var ratingRequest = URLRequest(url: ratingURL)
        if favorite {
            ratingRequest.httpMethod = "PUT"
            let body: [String: Any] = ["attributes": ["value": 1], "type": "ratings"]
            ratingRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            ratingRequest.httpMethod = "DELETE"
        }
        if favorite {
            let libraryURL = URL(string: "https://api.music.apple.com/v1/me/library?ids[albums]=\(albumId)")!
            var libraryRequest = URLRequest(url: libraryURL)
            libraryRequest.httpMethod = "POST"
            _ = try? await MusicDataRequest(urlRequest: libraryRequest).response()
        }
        _ = try? await MusicDataRequest(urlRequest: ratingRequest).response()
    }

    public func isAlbumFavorite(albumId: String) async throws -> Bool {
        let url = URL(string: "https://api.music.apple.com/v1/me/ratings/albums?ids=\(albumId)")!
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
        var queryItems = [URLQueryItem(name: "offset", value: String(offset))]
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

    public func getUserArtists(offset: Int = 0) async throws -> [AppleLibraryItem] {
        guard await requestMusicAuthorization() else { return [] }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/artists?limit=100&offset=\(offset)&extend=attributes")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
        let response = try? await request.response()
        guard let data = response?.data else { return [] }
        do {
            let appleUserPlaylistContainer = try decoder.decode(AppleLibraryContainer.self, from: data)
            return appleUserPlaylistContainer.data
        } catch {
            print(error)
            print(String(decoding: response!.data, as: UTF8.self))
            return []
        }
    }

    public func getUserAlbums(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/albums?offset=\(offset)&limit=25")!
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
    
    public func getUserSongs(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/songs?offset=\(offset)&limit=25&include=catalog")!
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
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.includeTopResults = true
        request.limit = 2
        guard let results = try? await request.response() else { return nil }
        return results.artists.first?.artwork?.url(width: size, height: size)
    }
    
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
    
    public func librarySearch(term: String) async throws -> AppleLibrarySearchContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let librarySongURL = URL(string: "https://api.music.apple.com/v1/me/library/search?term=\(term)&types=library-albums,library-artists,library-playlists,library-songs&limit=25")!
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
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids.map { MusicItemID($0) })
        let response = try await request.response()
        return Array(response.items)
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

