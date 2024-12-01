import Foundation

extension SonosAPI {
    func librarySearch(IP: String, query: String, filter: LibraryFilter = .track) async -> [PlayableContent] {
        let arguments: OrderedKeys = [
            ("ObjectID", "\(filter.id):\(query)"),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 100),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            print("Failed to send request.")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryLookup(IP: String, id: String) async -> [PlayableContent] {
        guard let objectID = id.components(separatedBy: "#").last else { return [] }
        
        let arguments: OrderedKeys = [
            ("ObjectID", objectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 100),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            print("Failed to send request.")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryAlbumLookup(IP: String, name: String) async -> [PlayableContent] {
        guard let albumName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let albumObjectID = "A:ALBUM/\(albumName)"
        
        let arguments: OrderedKeys = [
            ("ObjectID", albumObjectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 100),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            print("Failed to send request.")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryArtistLookup(IP: String, name: String) async -> [PlayableContent] {
        guard let artistName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let artistObjectID = "A:ALBUMARTIST/\(artistName)"

        let arguments: OrderedKeys = [
            ("ObjectID", artistObjectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 100),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            print("Failed to send request.")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func queueLibraryItem(ID: String, IP: String, position: QueuePosition = .next) async {
        var arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EnqueuedURI", ID),
            ("EnqueuedURIMetaData", ""),
            ("DesiredFirstTrackNumberEnqueued", 1),
            ("EnqueueAsNext", 1)
        ]

        switch position {
        case .front: break
        case .end:
            arguments.append(("DesiredFirstTrackNumberEnqueued", 0))
        case .now, .next:
            let index = await getCurrentTrack(ipAddress: IP)?.position ?? 1
            arguments.append(("DesiredFirstTrackNumberEnqueued", index + 1))
            arguments.append(("EnqueueAsNext", 1))
        }

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return
        }
    }

    func getLibraryItems(IP: String, type: ContentType, offset: Int = 0, requestedCount: Int = 0) async -> [PlayableContent] {
        let objectID: String
        switch type {
        case .artist:
            objectID = "A:ALBUMARTIST"
        case .track:
            objectID = "A:TRACKS:"
        case .album:
            objectID = "A:ALBUM"
        case .playlist:
            objectID = "SQ:"
        default:
            objectID = ""
        }

        let arguments: OrderedKeys = [
            ("ObjectID", objectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", offset),
            ("RequestedCount", requestedCount),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            print("Failed to send request.")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func refreshLibrary(IP: String) async {
        let arguments: OrderedKeys = [
            ("AlbumArtistDisplayOption", "")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "RefreshShareIndex", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            print("Failed to send request.")
            return
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Request failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return
        }
    }
}
