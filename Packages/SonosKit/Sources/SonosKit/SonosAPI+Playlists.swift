import Foundation

extension SonosAPI {
    func sonosPlaylists(IP: String) async -> [PlayableContent] {
        let arguments: [String: Any] = [
            "ObjectID": "SQ:",
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 0,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parsePlaylists(IP: IP, xml: xml)
    }

    func sonosPlaylistsTracks(IP: String, id: String) async -> [PlayableContent] {
        guard let objectID = id.components(separatedBy: "#").last else {
            return []
        }
        let arguments: [String: Any] = [
            "ObjectID": "SQ:" + objectID,
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 0,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parsePlaylistsTracks(IP: IP, xml: xml)
    }

    
    func removePlaylist(IP: String, itemID: String) async {
        guard let objectID = itemID.components(separatedBy: "#").last else { return  }

        let arguments: [String: Any] = [
            "ObjectID": "SQ:" + objectID,
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "DestroyObject", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else { return }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    private func getPlaylistUpdateID(IP: String, id: String) async -> String? {
        let arguments: [String: Any] = [
            "ObjectID": "SQ:" + id,
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 1,
            "SortCriteria": ""
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return nil
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseGetUpdateId(IP: IP, xml: xml)
    }

    func addToPlaylist(IP: String, playlistID: String, content: PlayableContent) async {
        guard let objectID = playlistID.components(separatedBy: "#").last else { return  }
        guard let updateID = await getPlaylistUpdateID(IP: IP, id: objectID) else { return }

        let arguments: [String: Any] = [
            "InstanceID": 0,
            "ObjectID": "SQ:" + objectID,
            "UpdateID": updateID,
            "EnqueuedURI": content.uri,
            "EnqueuedURIMetaData": content.URIMetadata,
            "AddAtIndex": Double(4294967295)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToSavedQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }
        
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func reorderSavedQueue(IP: String, from: Int, to: Int, savedQueueID: String) async {
        guard let objectID = savedQueueID.components(separatedBy: "#").last else { return  }
        guard let updateID = await getPlaylistUpdateID(IP: IP, id: objectID) else { return }

        let arguments: [String: Any] = [
            "InstanceID": 0,
            "ObjectID": "SQ:" + objectID,
            "TrackList": from,
            "NewPositionList": to,
            "UpdateID": updateID
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "ReorderTracksInSavedQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func removeTrackFromSavedQueue(IP: String, trackID: String, savedQueueID: String) async {
        guard let objectID = savedQueueID.components(separatedBy: "#").last else { return  }
        guard let updateID = await getPlaylistUpdateID(IP: IP, id: objectID) else { return }

        let arguments: [String: Any] = [
            "InstanceID": 0,
            "ObjectID": "SQ:" + objectID,
            "TrackList": trackID,
            "NewPositionList": "",
            "UpdateID": updateID
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "ReorderTracksInSavedQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func saveQueue(IP: String, title: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Title": title,
            "ObjectID": "",
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SaveQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func createPlaylist(IP: String, title: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Title": title,
            "EnqueuedURI": "",
            "EnqueuedURIMetaData": ""
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "CreateSavedQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func renamePlaylist(IP: String, playlistID: String, oldName: String, newName: String) async {
        guard let id = playlistID.components(separatedBy: "#").last else { return  }

        let arguments: [String: Any] = [
            "ObjectID": "SQ:" + id,
            "CurrentTagValue": "<dc:title>\(oldName)</dc:title>".encodeProgramURI,
            "NewTagValue": "<dc:title>\(newName)</dc:title>".encodeProgramURI,
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "UpdateObject", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

    }
}
