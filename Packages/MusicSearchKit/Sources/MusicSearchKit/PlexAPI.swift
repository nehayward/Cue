import Foundation
import SWXMLHash

public final class PlexAPI {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let parser = PlexParser()
    private var plexServer: PlexServer?

    @MainActor
    private let authenticator = PlexAuthenticator.shared

    @MainActor
    public var isAuthorized: Bool {
        authenticator.authToken != nil
    }

    public var serverID: String? {
        get {
            UserDefaults.standard.string(forKey: "com.clic.plexServer")
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "com.clic.plexServer")
        }
    }

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func search(for query: String, limit: Int = 15) async -> PlexResults? {
        guard let token = await authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard var search = plexServer.baseURL?.appending(path: "hubs/search") else { return nil }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        search.append(queryItems: queryItems)

        var request = URLRequest(url: search)
        request.httpMethod = "GET"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        return parser.parseXML(xmlData: data, plexServer: plexServer)
    }

    public func playlists() async -> [PlexUserPlaylist] {
        guard let plexServer = await getPlexServer() else {
            return []
        }

        guard var playlistsURL = plexServer.baseURL?.appending(path: "playlists") else { return [] }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "playlistType", value: "audio")
        ]
        playlistsURL.append(queryItems: queryItems)

        guard let playlistContainer: PlexContainer<PlexUserPlaylistContainer> = await loadAuthorized(playlistsURL) else {
            return []
        }

        var playlists = playlistContainer.mediaContainer.metadata
        guard let token = await authenticator.authToken else { return [] }

        for index in playlists.indices {
            playlists[index].sonosID = "\(plexServer.clientIdentifier)%3A3%3A\(playlists[index].ratingKey)"
            guard let composite = playlists[index].composite else { continue }
            playlists[index].thumbImageURL = plexServer.baseURL?.appending(path:  composite).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists
    }

    public func albums() async -> PlexLibraryItem? {
        guard let token = await authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard var playlistsURL = plexServer.baseURL?.appending(path: "playlists") else { return nil }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "playlistType", value: "audio"),
        ]
        playlistsURL.append(queryItems: queryItems)

        var request = URLRequest(url: playlistsURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibraryItem>.self, from: data).mediaContainer
            return PlexLibraryItem(
                size: container.size,
                allowSync: container.allowSync,
                art: container.art,
                grandparentRatingKey: container.grandparentRatingKey,
                grandparentThumb: container.grandparentThumb,
                grandparentTitle: container.grandparentTitle,
                identifier: container.identifier,
                key: container.key,
                librarySectionID: container.librarySectionID,
                librarySectionTitle: container.librarySectionTitle,
                librarySectionUUID: container.librarySectionUUID,
                mediaTagPrefix: container.mediaTagPrefix,
                mediaTagVersion: container.mediaTagVersion,
                nocache: container.nocache,
                parentIndex: container.parentIndex,
                parentTitle: container.parentTitle,
                parentYear: container.parentYear,
                summary: container.summary,
                thumb: container.thumb,
                title1: container.title1,
                title2: container.title2,
                viewGroup: container.viewGroup,
                viewMode: container.viewMode,
                metadata: await enrichMetadata(metadata: container.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupPlexSong(key: String) async -> PlexSongItem? {
        guard let token = await authenticator.authToken, let plexServer = await getPlexServer() else {
            return nil
        }

        guard let songURL = plexServer.baseURL?.appending(path: "library/metadata/\(key)") else {
            return nil
        }
        var request = URLRequest(url: songURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let mediaContainer = try decoder.decode(PlexContainer<PlexSongItem>.self, from: data).mediaContainer
            return PlexSongItem(
                size: mediaContainer.size,
                allowSync: mediaContainer.allowSync,
                librarySectionID: mediaContainer.librarySectionID,
                librarySectionTitle: mediaContainer.librarySectionTitle,
                metadata: await enrichMetadata(metadata: mediaContainer.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupAlbum(key: String) async -> PlexLibraryItem? {
        guard let token = await authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard let albumURL = plexServer.baseURL?.appending(path: "library/metadata/\(key)/children") else { return nil }
        var request = URLRequest(url: albumURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibraryItem>.self, from: data).mediaContainer
            return PlexLibraryItem(
                size: container.size,
                allowSync: container.allowSync,
                art: container.art,
                grandparentRatingKey: container.grandparentRatingKey,
                grandparentThumb: container.grandparentThumb,
                grandparentTitle: container.grandparentTitle,
                identifier: container.identifier,
                key: container.key,
                librarySectionID: container.librarySectionID,
                librarySectionTitle: container.librarySectionTitle,
                librarySectionUUID: container.librarySectionUUID,
                mediaTagPrefix: container.mediaTagPrefix,
                mediaTagVersion: container.mediaTagVersion,
                nocache: container.nocache,
                parentIndex: container.parentIndex,
                parentTitle: container.parentTitle,
                parentYear: container.parentYear,
                summary: container.summary,
                thumb: container.thumb,
                title1: container.title1,
                title2: container.title2,
                viewGroup: container.viewGroup,
                viewMode: container.viewMode,
                metadata: [],
                sonosID: "\(plexServer.clientIdentifier)%3A3%3A\(container.key)",
                thumbImageURL: plexServer.baseURL?.appending(path: container.thumb)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupAlbumTracks(key: String) async -> PlexLibraryItem? {
        guard let token = await authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard let albumURL = plexServer.baseURL?.appending(path: "library/metadata/\(key)/children") else { return nil }
        var request = URLRequest(url: albumURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibraryItem>.self, from: data).mediaContainer
            return PlexLibraryItem(
                size: container.size,
                allowSync: container.allowSync,
                art: container.art,
                grandparentRatingKey: container.grandparentRatingKey,
                grandparentThumb: container.grandparentThumb,
                grandparentTitle: container.grandparentTitle,
                identifier: container.identifier,
                key: container.key,
                librarySectionID: container.librarySectionID,
                librarySectionTitle: container.librarySectionTitle,
                librarySectionUUID: container.librarySectionUUID,
                mediaTagPrefix: container.mediaTagPrefix,
                mediaTagVersion: container.mediaTagVersion,
                nocache: container.nocache,
                parentIndex: container.parentIndex,
                parentTitle: container.parentTitle,
                parentYear: container.parentYear,
                summary: container.summary,
                thumb: container.thumb,
                title1: container.title1,
                title2: container.title2,
                viewGroup: container.viewGroup,
                viewMode: container.viewMode,
                metadata: await enrichMetadata(metadata: container.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupPlaylists(key: String) async -> PlexPlaylistItem? {
        guard let token = await authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard let albumURL = plexServer.baseURL?.appending(path: "playlists/\(key)/items") else { return nil }
        var request = URLRequest(url: albumURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let mediaContainer = try decoder.decode(PlexContainer<PlexPlaylistItem>.self, from: data).mediaContainer
            return PlexPlaylistItem(
                size: mediaContainer.size,
                ratingKey: mediaContainer.ratingKey,
                duration: mediaContainer.duration,
                title: mediaContainer.title,
                metadata: await enrichMetadata(metadata: mediaContainer.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupArtist(key: String) async -> PlexMetadata? {
        guard let plexServer = await getPlexServer(),
              let artistURL = plexServer.baseURL?.appending(path: "library/metadata/\(key)") else {
            return nil
        }

        guard let playlistContainer: PlexContainer<PlexArtistContainer> = await loadAuthorized(artistURL) else {
            return nil
        }

        guard var artist = playlistContainer.mediaContainer.metadata.first,
              let token = await authenticator.authToken else { return nil }

        artist.sonosID = "\(plexServer.clientIdentifier)%3A3%3A\(artist.ratingKey)"
        artist.thumbImageURL = plexServer.baseURL?.appending(path: artist.thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        return artist
    }

    public func lookupArtistAlbums(key: String) async -> PlexLibraryItem? {
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard let artistURL = plexServer.baseURL?.appending(path: "library/metadata/\(key)/children") else { return nil }
        guard let plexContainer: PlexContainer<PlexLibraryItem> = await loadAuthorized(artistURL) else { return nil }
        let container = plexContainer.mediaContainer
        return PlexLibraryItem(
            size: container.size,
            allowSync: container.allowSync,
            art: container.art,
            grandparentRatingKey: container.grandparentRatingKey,
            grandparentThumb: container.grandparentThumb,
            grandparentTitle: container.grandparentTitle,
            identifier: container.identifier,
            key: container.key,
            librarySectionID: container.librarySectionID,
            librarySectionTitle: container.librarySectionTitle,
            librarySectionUUID: container.librarySectionUUID,
            mediaTagPrefix: container.mediaTagPrefix,
            mediaTagVersion: container.mediaTagVersion,
            nocache: container.nocache,
            parentIndex: container.parentIndex,
            parentTitle: container.parentTitle,
            parentYear: container.parentYear,
            summary: container.summary,
            thumb: container.thumb,
            title1: container.title1,
            title2: container.title2,
            viewGroup: container.viewGroup,
            viewMode: container.viewMode,
            metadata: await enrichMetadata(metadata: container.metadata)
        )
    }

    public func getPlexServers() async -> [PlexServer] {
        let resourceURL = URL(string: "https://plex.tv/api/v2/resources")!
        guard let plexServers: [PlexServer] = await loadAuthorized(resourceURL) else {
            return []
        }
        return plexServers
    }

    private func getPlexServer() async -> PlexServer? {
        if let plexServer {
            return plexServer
        }
        let plexServers = await getPlexServers()
        let preferredServer = plexServers.filter { $0.clientIdentifier == serverID }.first
        self.plexServer = preferredServer
        return preferredServer
    }

    private func authorizedRequest(from url: URL) async -> URLRequest? {
        guard let token = await authenticator.authToken else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    private func loadAuthorized<T: Decodable>(_ url: URL) async -> T? {
        guard let request = await authorizedRequest(from: url) else {
            return nil
        }
        guard let (data, urlResponse) = try? await session.data(for: request) else { return nil }
        
        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // MARK: Reset
            Task { @MainActor in
                authenticator.authToken = nil
                serverID = nil
            }
            return nil
        }

        do {
            let response = try decoder.decode(T.self, from: data)
            return response
        } catch {
            print(error)
            assertionFailure(String(decoding: data, as: UTF8.self))
            return nil
        }
    }

    private func enrichMetadata(metadata: [PlexMetadata]?) async -> [PlexMetadata] {
        guard let token = await authenticator.authToken, 
                let clientID = plexServer?.clientIdentifier,
                let metadata else { return [] }

        return metadata.map { item in
            var updatedItem = item
            updatedItem.sonosID = "\(clientID)%3A3%3A\(item.ratingKey)"
            updatedItem.thumbImageURL = plexServer?.baseURL?.appending(path: item.thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            return updatedItem
        }
    }
}
