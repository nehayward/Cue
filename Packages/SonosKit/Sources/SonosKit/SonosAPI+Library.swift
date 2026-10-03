import DanceLogger
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
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryLookup(IP: String, id: String, offset: Int = 0, requestedCount: Int = 100) async -> [PlayableContent] {
        guard let objectID = id.components(separatedBy: "#").last else { return [] }

        let arguments: OrderedKeys = [
            ("ObjectID", objectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", offset),
            ("RequestedCount", requestedCount),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }
    
    
    func libraryPlaylistLookup(IP: String, id: String) async -> [PlayableContent] {
        guard let objectID = id.components(separatedBy: "#").last else { return [] }
        
        let arguments: OrderedKeys = [
            ("ObjectID", objectID),
            ("BrowseFlag", "BrowseMetadata"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 100),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    func libraryAlbumLookup(IP: String, name: String) async -> [PlayableContent] {
        guard let albumName = name.addingPercentEncoding(withAllowedCharacters: .sonosQueryAllowed) else { return [] }
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
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
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
            ("RequestedCount", 200),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }

    /// How many items the speaker's index holds for a content type, from the
    /// `TotalMatches` every Browse response carries. One request with a single
    /// item asked for: enough to size a sync and to tell whether a cached copy
    /// still matches the library.
    func libraryItemCount(IP: String, type: ContentType) async -> Int? {
        let arguments: OrderedKeys = [
            ("ObjectID", Self.objectID(for: type)),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 1),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory"),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
        else { return nil }

        // Read straight off the envelope rather than teaching the item parser
        // to carry a count it has no other use for.
        let xml = String(decoding: data, as: UTF8.self)
        guard let range = xml.range(of: "<TotalMatches>"),
              let end = xml.range(of: "</TotalMatches>", range: range.upperBound..<xml.endIndex)
        else { return nil }
        return Int(xml[range.upperBound..<end.lowerBound])
    }

    /// The speaker's index key for a content type.
    static func objectID(for type: ContentType) -> String {
        switch type {
        case .artist: "A:ALBUMARTIST"
        case .track: "A:TRACKS:"
        case .album: "A:ALBUM"
        case .playlist: "SQ:"
        default: ""
        }
    }

    func getLibraryItems(IP: String, type: ContentType, offset: Int = 0, requestedCount: Int = 0) async -> [PlayableContent] {
        let arguments: OrderedKeys = [
            ("ObjectID", Self.objectID(for: type)),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", offset),
            ("RequestedCount", requestedCount),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseLibrarySearch(IP: IP, xml: xml)
    }
    
    func getLibraryItems(IP: String, type: String, filter: String = "*", offset: Int = 0, requestedCount: Int = 0) async -> [PlayableContent] {
        let arguments: OrderedKeys = [
            ("ObjectID", type),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", filter),
            ("StartingIndex", offset),
            ("RequestedCount", requestedCount),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            DanceLog.sonos.error("\(#function): request failed")
            return []
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
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
            DanceLog.sonos.error("\(#function): request failed")
            return
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            DanceLog.sonos.error("\(#function): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return
        }
    }
}
