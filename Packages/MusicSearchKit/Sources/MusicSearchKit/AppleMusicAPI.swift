import Foundation
import MusicKit

public final class AppleMusicAPI {
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
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

    public func getUserArtists() async throws -> [AppleLibraryItem] {
        guard await requestMusicAuthorization() else { return [] }

        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/artists?extend=attributes")!
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

    public func lookupUsersPlaylist(id: String) async throws -> Playlist? {
        guard await requestMusicAuthorization() else { return nil }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        return response.items.first
    }

    public func lookupUsersLibraryPlaylist(id: String) async throws -> AppleLibraryContainer? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistsURL = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(id)/tracks")!
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

