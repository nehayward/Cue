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
        var id: String = songId
        if songId.hasPrefix("i") {
            guard let catalogSong = try? await librarySongCatalog(id: songId),
                  let song = catalogSong.data.first else {
                return
            }
            id = song.id
            let ratingURL = URL(string: "https://api.music.apple.com/v1/me/ratings/songs/\(id)")!
            var urlRequest = URLRequest(url: ratingURL)
            
            if favorite {
                // Set favorite status with PUT
                urlRequest.httpMethod = "PUT"
                let body: [String: Any] = [
                    "attributes": [
                        "value": 1
                    ],
                    "type": "ratings"
                ]
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            } else {
                // Remove favorite status with DELETE
                urlRequest.httpMethod = "DELETE"
            }
            
            let request = MusicDataRequest(urlRequest: urlRequest)
            guard let response = try? await request.response() else {
                return
            }
            print(String(decoding: response.data, as: UTF8.self))
        } else {
#if !targetEnvironment(macCatalyst) && !os(macOS)
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songId))
            let response = try await request.response()
            
            if let song = response.items.first {
                print(song.id.rawValue)
                try await MusicLibrary.shared.add(song)
                print("Song added to library successfully")
            } else {
                print("Song not found")
            }
#endif            
        }
    }
    
    public func isFavorite(songId: String) async throws -> Bool {
        guard let catalogSong = try? await librarySongCatalog(id: songId), let id = catalogSong.data.first?.id else { return false }
        let addToPlaylistURL = URL(string: "https://api.music.apple.com/v1/me/ratings/songs?ids=\(id)")!
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
    
    public func addSongToPlaylist(songId: String, playlistID: String) async throws {
        let ratingURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistID)/tracks")!
        var urlRequest = URLRequest(url: ratingURL)
        
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "data": [
                [
                    "id": "i.\(songId)",
                    "type": "songs"
                ]
            ]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let request = MusicDataRequest(urlRequest: urlRequest)
        guard let response = try? await request.response() else {
            return
        }
        print(String(decoding: response.data, as: UTF8.self))
    }
        
    public func getUserPlaylists(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists?offset=\(offset)")!
        let request = MusicDataRequest(urlRequest: .init(url: playlistsURL))
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

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/songs?offset=\(offset)&limit=25")!
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
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(id)/tracks?offset=\(offset)")!
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
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/albums/\(id)/tracks")!
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

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/recent/played?offset=\(offset)&limit=10")!
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

    public func lookupUsersRecentAddedTracks(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/recently-added?offset=\(offset)&limit=25")!
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
    
    public func lookupUsersRecentRadioStations(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let radioStationsURL = URL(string: "https://api.music.apple.com/v1/me/recent/radio-stations?offset=\(offset)&limit=25")!
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
    
    public func lookupAppleRadioStations(offset: Int = 0) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }

        let region = (Locale.current.region?.identifier ?? "US").lowercased()
        let radioStationsURL = URL(string: "https://api.music.apple.com/v1/catalog/\(region)/stations?filter[identity]=personal")!
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
    
    public func artistArtwork(for name: String) async -> URL? {
        guard await requestMusicAuthorization() else { return nil }
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.includeTopResults = true
        request.limit = 2
        guard let results = try? await request.response() else { return nil }
        return results.artists.first?.artwork?.url(width: 100, height: 100)
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

