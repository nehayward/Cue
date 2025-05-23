import Foundation
import SwiftyBeaver

public final class PlexAPI {
    public static var shared = PlexAPI()
    private let session: URLSession
    private let decoder: JSONDecoder
    private let parser = PlexParser()
    private var plexServer: PlexServer?
    private let logger = SwiftyBeaver.self
    private var cachedAlbumLibrarySection: String?

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
        self.decoder.dateDecodingStrategy = .secondsSince1970

        let console = ConsoleDestination()  // log to Xcode Console
        let file = FileDestination()  // log to default swiftybeaver.log file
        file.format = "$J"
        console.logPrintWay = .logger(subsystem: "Main", category: "UI")
        logger.addDestination(console)
//        logger.addDestination(file)
//        print("Init")
    }

    public func search(for query: String, limit: Int = 50) async -> PlexResults? {
        guard let token = await authenticator.authToken,
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
        guard let token = await authenticator.authToken, let id = plexServer.clientIdentifier else { return [] }

        for index in playlists.indices {
            playlists[index].sonosID = "\(id)%3A3%3A\(playlists[index].ratingKey)"
            guard let composite = playlists[index].composite else { continue }
            playlists[index].thumbImageURL = plexServer.baseURL?.appending(path:  composite).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists
    }
    
    public enum AlbumSortOrder {
        case titleAscending
        case titleDescending
        
        var queryValue: String {
            switch self {
            case .titleAscending:
                return "titleSort:asc"
            case .titleDescending:
                return "titleSort:desc"
            }
        }
    }
    
    public func artists(
        sortOrder: AlbumSortOrder = .titleAscending,
        offset: Int = 0,
        limit: Int = 100
    ) async -> [PlexMetadata] {
        guard let plexServer = await getPlexServer() else {
            return []
        }
        logger.info(plexServer)
        
        // Get and cache music library section if needed
        if cachedAlbumLibrarySection == nil {
           cachedAlbumLibrarySection = await getMusicLibrarySection()
        }
        
        guard let sectionKey = cachedAlbumLibrarySection,
              var albumURL = plexServer.baseURL?.appending(path: "/library/sections/\(sectionKey)/all") else {
            return []
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "8"),
            URLQueryItem(name: "sort", value: sortOrder.queryValue),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let artistsContainer: PlexContainer<PlexArtistContainer> = await loadAuthorized(albumURL) else {
            return []
        }

        guard var artists = artistsContainer.mediaContainer.metadata else { return [] }
        guard let token = await authenticator.authToken, let id = plexServer.clientIdentifier else { return [] }

        for index in artists.indices {
            artists[index].sonosID = "\(id)%3A3%3A\(artists[index].ratingKey)"
            guard let thumb = artists[index].thumb else { continue }
            artists[index].thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return artists
    }

    
    public func albums(
        sortOrder: AlbumSortOrder = .titleAscending,
        offset: Int = 0,
        limit: Int = 100
    ) async -> [PlexAlbumItem] {
        guard let plexServer = await getPlexServer() else {
            return []
        }
        logger.info(plexServer)
        
        // Get and cache music library section if needed
        if cachedAlbumLibrarySection == nil {
           cachedAlbumLibrarySection = await getMusicLibrarySection()
        }
        
        guard let sectionKey = cachedAlbumLibrarySection,
              var albumURL = plexServer.baseURL?.appending(path: "/library/sections/\(sectionKey)/all") else {
            return [] 
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "9"),
            URLQueryItem(name: "sort", value: sortOrder.queryValue),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let playlistContainer: PlexContainer<PlexAlbumContainer> = await loadAuthorized(albumURL) else {
            return []
        }

        guard var playlists = playlistContainer.mediaContainer.metadata else { return [] }
        guard let token = await authenticator.authToken, let id = plexServer.clientIdentifier else { return [] }

        for index in playlists.indices {
            playlists[index].sonosID = "\(id)%3A3%3A\(playlists[index].ratingKey)"
            guard let thumb = playlists[index].thumb else { continue }
            playlists[index].thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists
    }
    
    public func songs(
        sortOrder: AlbumSortOrder = .titleAscending,
        offset: Int = 0,
        limit: Int = 100
    ) async -> [PlexMetadata] {
        guard let plexServer = await getPlexServer() else {
            return []
        }
        logger.info(plexServer)
        
        // Get and cache music library section if needed
        if cachedAlbumLibrarySection == nil {
           cachedAlbumLibrarySection = await getMusicLibrarySection()
        }
        
        guard let sectionKey = cachedAlbumLibrarySection,
              var albumURL = plexServer.baseURL?.appending(path: "/library/sections/\(sectionKey)/all") else {
            return []
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "sort", value: sortOrder.queryValue),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let songContainer: PlexContainer<PlexSongItem> = await loadAuthorized(albumURL) else {
            return []
        }

        guard var songs = songContainer.mediaContainer.metadata else { return [] }
        guard let token = await authenticator.authToken, let id = plexServer.clientIdentifier else { return [] }

        for index in songs.indices {
            songs[index].sonosID = "\(id)%3A3%3A\(songs[index].ratingKey)"
            guard let thumb = songs[index].thumb else { continue }
            songs[index].thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return songs
    }


    private func getMusicLibrarySection() async -> String? {
        guard let token = await authenticator.authToken,
              let plexServer = await getPlexServer() else {
            return nil
        }

        guard let sectionsURL = plexServer.baseURL?.appending(path: "library/sections") else {
            return nil
        }

        var request = URLRequest(url: sectionsURL)
        request.httpMethod = "GET" 
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibrarySectionContainer>.self, from: data)
            let musicSection = container.mediaContainer.Directory
                .sorted(by: { $0.key < $1.key })
                .first { $0.type == "artist" }
            return musicSection?.key
        } catch {
            logger.error(error)
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
                metadata: await enrichMetadata(metadata: container.metadata)
            )
        } catch {
            print(error)
            return nil
        }
    }

    public func lookupPlaylist(key: String, type: PlexMediaType, ascending: Bool, offset: Int = 0) async -> PlexPlaylistItem? {
        guard let token = await authenticator.authToken else { return nil }
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard var playlistURL = plexServer.baseURL?.appending(path: "playlists/\(key)/items") else { return nil }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type.rawValue.description),
            URLQueryItem(name: "sort", value: ascending ? "titleSort:asc" : "titleSort:desc"),
        ]
        
        playlistURL.append(queryItems: queryItems)

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

        guard var artist = playlistContainer.mediaContainer.metadata?.first,
              let token = await authenticator.authToken else { return nil }

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
        return plexServers.filter { $0.accessToken != nil }
    }

    private func getPlexServer() async -> PlexServer? {
//        let jsonData = """
// {
//        "name": "The Mothership",
//        "product": "Plex Media Server",
//        "productVersion": "1.41.0.8992-8463ad060",
//        "platform": "MacOSX",
//        "platformVersion": "15.0.0",
//        "device": "Mac14,3",
//        "clientIdentifier": "883946cf10e29d817ec3f89bf8ae36d14978176a",
//        "createdAt": "2016-09-04T19:10:07Z",
//        "lastSeenAt": "2024-09-16T22:00:39Z",
//        "provides": "server",
//        "ownerId": null,
//        "sourceTitle": null,
//        "publicAddress": "212.159.69.190",
//        "accessToken": "KSAM-R573sKNdDdk2i-G",
//        "owned": true,
//        "home": false,
//        "synced": false,
//        "relay": true,
//        "presence": true,
//        "httpsRequired": false,
//        "publicAddressMatches": false,
//        "dnsRebindingProtection": false,
//        "natLoopbackSupported": true,
//        "connections": [
//          {
//            "protocol": "https",
//            "address": "192.168.135.254",
//            "port": 32400,
//            "uri": "https://192-168-135-254.b9c7c12bf5f64e85a1a12a53f4e74f69.plex.direct:32400",
//            "local": true,
//            "relay": false,
//            "IPv6": false
//          },
//          {
//            "protocol": "https",
//            "address": "212.159.69.190",
//            "port": 50000,
//            "uri": "https://212-159-69-190.b9c7c12bf5f64e85a1a12a53f4e74f69.plex.direct:50000",
//            "local": false,
//            "relay": false,
//            "IPv6": false
//          },
//          {
//            "protocol": "https",
//            "address": "178.79.176.52",
//            "port": 8443,
//            "uri": "https://178-79-176-52.b9c7c12bf5f64e85a1a12a53f4e74f69.plex.direct:8443",
//            "local": false,
//            "relay": true,
//            "IPv6": false
//          }
//        ]
//      }
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
        let xml = String(decoding: data, as: UTF8.self)
        logger.info("\(xml)")
        do {
            let response = try decoder.decode(T.self, from: data)
            return response
        } catch {
            print(String(decoding: data, as: UTF8.self))
            print(error)
            assertionFailure(String(decoding: data, as: UTF8.self))
            return nil
        }
    }

    private func enrichMetadata(metadata: [PlexMetadata]?) async -> [PlexMetadata] {
        guard let token = await authenticator.authToken,
                let plexServer = await getPlexServer(),
                let clientID = plexServer.clientIdentifier,
                let metadata else { return [] }

        return metadata.map { item in
            var updatedItem = item
            updatedItem.sonosID = "\(clientID)%3A3%3A\(item.ratingKey)"
            if let thumb = item.thumb {
                updatedItem.thumbImageURL = plexServer.baseURL?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
            
            if let art = item.art {
                updatedItem.artImageURL = plexServer.baseURL?.appending(path: art).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
            
            return updatedItem
        }
    }
}
