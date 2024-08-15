import Foundation
import SWXMLHash
import SwiftyBeaver

public final class PlexAPI {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let parser = PlexParser()
    private var plexServer: PlexServer?
    private let logger = SwiftyBeaver.self

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

        let console = ConsoleDestination()  // log to Xcode Console
        let file = FileDestination()  // log to default swiftybeaver.log file
        file.format = "$J"
        console.logPrintWay = .logger(subsystem: "Main", category: "UI")
        logger.addDestination(console)
        logger.addDestination(file)
    }

    public func search(for query: String, limit: Int = 50) async -> PlexResults? {
        guard let token = authenticator.authToken,
              let plexServer = await getPlexServer() else {
            logger.info("No server")
            return nil
        }

        guard var search = plexServer.baseURL?.appending(path: "hubs/search") else {
            logger.warning("Token: \(token)")
            logger.warning("Plex invalid url \(plexServer.name)")
            return nil
        }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "sectionId", value: "3"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        search.append(queryItems: queryItems)

        var request = URLRequest(url: search)
        request.httpMethod = "GET"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            logger.warning("Search request failed \(String(describing: request.url?.absoluteString))")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        logger.info("\(xml)")
        return parser.parseXML(xmlData: data, plexServer: plexServer)
    }

    public func playlists() async -> [PlexUserPlaylist] {
        guard let plexServer = await getPlexServer() else {
            return []
        }
        logger.info(plexServer)

        guard var playlistsURL = plexServer.baseURL?.appending(path: "playlists") else { return [] }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "playlistType", value: "audio")
        ]
        playlistsURL.append(queryItems: queryItems)

        guard let playlistContainer: PlexContainer<PlexUserPlaylistContainer> = await loadAuthorized(playlistsURL) else {
            return []
        }

        var playlists = playlistContainer.mediaContainer.metadata
        guard let token = authenticator.authToken, let id = plexServer.clientIdentifier else { return [] }

        for index in playlists.indices {
            playlists[index].sonosID = "\(id)%3A3%3A\(playlists[index].ratingKey)"
            guard let composite = playlists[index].composite else { continue }
            playlists[index].thumbImageURL = plexServer.baseURL?.appending(path:  composite).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists
    }

    public func albums() async -> PlexLibraryItem? {
        guard let token = authenticator.authToken else { return nil }
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
                metadata: await enrichMetadata(metadata: container.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupPlexSong(key: String) async -> PlexSongItem? {
        guard let token = authenticator.authToken, let plexServer = await getPlexServer() else {
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
        guard let token = authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer(), let id = plexServer.clientIdentifier else {
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
            var thumbImageURL: URL? = nil
            if let thumb = container.thumb {
                thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
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
                metadata: [],
                sonosID: "\(id)%3A3%3A\(container.key)",
                thumbImageURL: thumbImageURL
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupAlbumTracks(key: String) async -> PlexLibraryItem? {
        guard let token = authenticator.authToken else { return nil }
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
                metadata: await enrichMetadata(metadata: container.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupPlaylist(key: String, offset: Int = 0) async -> PlexPlaylistItem? {
        guard let token = authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard let playlistURL = plexServer.baseURL?.appending(path: "playlists/\(key)/items") else { return nil }
        var request = URLRequest(url: playlistURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.addValue("\(offset)", forHTTPHeaderField: "X-Plex-Container-Start")
        request.addValue("200", forHTTPHeaderField: "X-Plex-Container-Size")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let mediaContainer = try decoder.decode(PlexContainer<PlexPlaylistItem>.self, from: data).mediaContainer
            return PlexPlaylistItem(
                size: mediaContainer.size,
                totalSize: mediaContainer.totalSize,
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
              let artistURL = plexServer.baseURL?.appending(path: "library/metadata/\(key)"),
              let id = plexServer.clientIdentifier else {
            return nil
        }

        guard let playlistContainer: PlexContainer<PlexArtistContainer> = await loadAuthorized(artistURL) else {
            return nil
        }

        guard var artist = playlistContainer.mediaContainer.metadata.first,
              let token = authenticator.authToken else { return nil }

        artist.sonosID = "\(id)%3A3%3A\(artist.ratingKey)"
        if let thumb = artist.thumb {
            artist.thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }
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
            metadata: await enrichMetadata(metadata: container.metadata)
        )
    }

    public func getPlexServers() async -> [PlexServer] {
        let resourceURL = URL(string: "https://plex.tv/api/v2/resources")!
        guard let plexServers: [PlexServer] = await loadAuthorized(resourceURL) else {
            return []
        }
        logger.info(plexServers)
        return plexServers
    }

    private func getPlexServer() async -> PlexServer? {
//        let jsonData = """
// {
//    "name": "ALUNA",
//    "product": "Plex Media Server",
//    "productVersion": "1.40.4.8679-424562606",
//    "platform": "Linux",
//    "platformVersion": "DSM 7.2.1.69057-3",
//    "device": "DS920+",
//    "clientIdentifier": "d6812b5a755e0118d223ca98b19a4b3da95b1470",
//    "createdAt": "2021-01-24T21:10:24Z",
//    "lastSeenAt": "2024-07-30T23:54:18Z",
//    "provides": "server",
//    "ownerId": null,
//    "sourceTitle": null,
//    "publicAddress": "70.112.150.77",
//    "accessToken": "yz9Qj6sMATJfJQc2Jnsq",
//    "owned": true,
//    "home": false,
//    "synced": false,
//    "relay": true,
//    "presence": true,
//    "httpsRequired": false,
//    "publicAddressMatches": true,
//    "dnsRebindingProtection": false,
//    "natLoopbackSupported": true,
//    "connections": [
//      {
//        "protocol": "http",
//        "address": "192.168.50.187",
//        "port": 32400,
//        "uri": "http://192.168.50.187:32400",
//        "local": true,
//        "relay": false,
//        "IPv6": false
//      },
//      {
//        "protocol": "http",
//        "address": "QuickConnect.to",
//        "port": 29463,
//        "uri": "http://QuickConnect.to:29463",
//        "local": false,
//        "relay": false,
//        "IPv6": false
//      },
//      {
//        "protocol": "http",
//        "address": "70.112.150.77",
//        "port": 29463,
//        "uri": "http://70.112.150.77:29463",
//        "local": false,
//        "relay": false,
//        "IPv6": false
//      }
//    ]
//  }
//"""
//        return try? JSONDecoder().decode(PlexServer.self, from: jsonData.data(using: .utf8)!)
        if let plexServer {
            return plexServer
        }
        let plexServers = await getPlexServers()
        let preferredServer = plexServers.filter { $0.clientIdentifier == serverID }.first
        self.plexServer = preferredServer
        return preferredServer
    }

    private func authorizedRequest(from url: URL) async -> URLRequest? {
        guard let token = authenticator.authToken else { return nil }
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
        let xml = String(decoding: data, as: UTF8.self)
        logger.info("\(xml)")
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
        guard let token = authenticator.authToken,
                let plexServer = await getPlexServer(),
                let clientID = plexServer.clientIdentifier,
                let metadata else { return [] }

        return metadata.map { item in
            var updatedItem = item
            updatedItem.sonosID = "\(clientID)%3A3%3A\(item.ratingKey)"
            if let thumb = item.thumb {
                updatedItem.thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
            return updatedItem
        }
    }
}
