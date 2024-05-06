import Foundation

extension SonosAPI {
    func librarySearch(IP: String, query: String, filter: LibraryFilter = .track) async -> [PlayableContent] {
        let arguments: [String: Any] = [
            "ObjectID": "\(filter.id):\(query)",
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 100,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryLookup(IP: String, id: String) async -> [PlayableContent] {
        guard let objectID = id.components(separatedBy: "#").last else { return [] }
        
        let arguments: [String: Any] = [
            "ObjectID": objectID,
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 100,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryAlbumLookup(IP: String, name: String) async -> [PlayableContent] {
        guard let albumName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let albumObjectID = "A:ALBUM/\(albumName)"
        let arguments: [String: Any] = [
            "ObjectID": albumObjectID,
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 100,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryArtistLookup(IP: String, name: String) async -> [PlayableContent] {
        guard let artistName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let artistObjectID = "A:ALBUMARTIST/\(artistName)"

        let arguments: [String: Any] = [
            "ObjectID": artistObjectID,
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 100,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func queueLibraryItem(ID: String, IP: String, position: QueuePosition = .next) async {
        var arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": ID,
            "EnqueuedURIMetaData": "",
            "DesiredFirstTrackNumberEnqueued": 1,
            "EnqueueAsNext": 1
        ]

        switch position {
        case .front: break
        case .end:
            arguments["DesiredFirstTrackNumberEnqueued"] = 0
        case .now, .next:
            let index = await getCurrentTrack(ipAddress: IP)?.position ?? 1
            arguments["DesiredFirstTrackNumberEnqueued"] = index + 1
            arguments["EnqueueAsNext"] = 1
        }

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func refreshLibrary(IP: String) async {
        let arguments: [String: Any] = [
            "AlbumArtistDisplayOption": ""
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "RefreshShareIndex", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }
}
