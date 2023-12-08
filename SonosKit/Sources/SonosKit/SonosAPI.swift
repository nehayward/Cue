import Foundation
import OSLog
import Network

final class SonosAPI {
    private let logger: Logger = Logger(subsystem: "com.sonos.nick", category: "SonosAPI")
    private lazy var session: URLSession = privateSession

    private lazy var privateSession: URLSession = {
        let configuration: URLSessionConfiguration = .default
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 3
        return URLSession(configuration: configuration)
    }()

    func setVolume(ipAddress: String, volume: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
            "DesiredVolume": volume
        ]

        if let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "SetVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
        }
    }

    func getGroupMute(IP: String) async -> Bool {
        let arguments: [String: Any] = [
            "InstanceID": 0
        ]

        if let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetGroupMute", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
            let xml = String(decoding: data, as: UTF8.self)
            return XMLParserSonos().parseGetGroupMute(xml: xml)
        }

        return false
    }

    func setGroupMute(IP: String, mute: Bool) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "DesiredMute": mute ? 1 : 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetGroupMute", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                // TODO: Throw error
            }
        }
    }

    func setRelativeVolume(ipAddress: String, volume: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
            "Adjustment": volume
        ]

        if let (_, _) = try? await sendSoapRequest(ip: ipAddress, action: "SetRelativeVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") {
        }
    }

    func setRelativeGroupVolume(ipAddress: String, volume: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Adjustment": volume
        ]

        try? await sendSoapRequest(ip: ipAddress, action: "SetRelativeGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl")
    }

    func getVolume(ipAddress: String) async throws -> Double {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
        ]

        guard let (data, _) = try await sendSoapRequest(ip: ipAddress, action: "GetVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            throw SonosAPIError.requestBuild
        }

        let xml = String(decoding: data, as: UTF8.self)
        let volume = try XMLParserSonos().parseVolume(xml: xml)
        return Double(volume)
    }

    @discardableResult func getGroupVolume(ipAddress: String) async throws -> Double {
        let arguments: [String: Any] = [
            "InstanceID": 0
        ]

        guard let (data, _) = try await sendSoapRequest(ip: ipAddress, action: "GetGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else {
            throw SonosAPIError.requestBuild
        }
        
        let xml = String(decoding: data, as: UTF8.self)
        let volume = try XMLParserSonos().parseGroupVolume(xml: xml)
        return Double(volume)
    }

    func setGroupVolume(ipAddress: String, volume: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "DesiredVolume": volume
        ]

        if let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "SetGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
//            let xml = String(decoding: data, as: UTF8.self)
//            print(xml)
        }
    }



    func snapshotGroupVolume(ipAddress: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "SnapshotGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return }
            print(xmlString)
        }

        return
    }

    func getCurrentTrack(ipAddress: String) async -> Track? {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetPositionInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
            let trackInfo = XMLParserSonos().parsePositionInfo(xml: xmlString.unescaped)
            return trackInfo
        }

        return nil
    }

    func pause(ipAddress: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        if let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Pause", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
        }
    }

    func play(ipAddress: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Speed": 1
        ]

        if let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Play", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
                print(response)
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
        }
    }

    func next(ipAddress: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Speed": 1
        ]

        if let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Next", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
        }
    }


    func previous(ipAddress: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Previous", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
        }
    }

    func isPlaying(ipAddress: String) async -> PlaybackStatus {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetTransportInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            let xmlString = String(data: data, encoding: .utf8)!
            let playbackInfo = XMLParserSonos().parsePlaybackInfo(xml: xmlString)
            return playbackInfo
        }

        return .transitioning
    }

    public func playMode(_ IP: String) async -> PlayMode {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetTransportSettings", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else  {
            return .normal
        }
        let xml = String(decoding: data, as: UTF8.self)
        return XMLParserSonos().parsePlaybackMode(xml) ?? .normal
    }

    public func setPlayMode(_ IP: String, playMode: PlayMode) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "NewPlayMode": playMode.sonosMode.uppercased()
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "SetPlayMode", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else  {
            return
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            print("Failed")
            return
        }
        let xml = String(decoding: data, as: UTF8.self)
        print(xml)
    }


    func mediaInfo(ipAddress: String) async -> Bool {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetMediaInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return false }
            let isTVMode = XMLParserSonos().parseMediaInfo(xml: xmlString)
            return isTVMode
        }

        return false
    }


    func getBatteryLevel(ipAddress: String) {
//        guard let url = URL(string: "http://\(ipAddress):1400/status/batterystatus") else { return }
//        let request = URLRequest(url: url)
    }

    func getGroups(ipAddress: String) async throws -> [GroupRoom] {
        do {
            if let (data, _) = try await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: [:], endpoint: "ZoneGroupTopology") {
                guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
                let zones = XMLParserSonos().parseZones(xml: xmlString.unescaped)
                return zones.compactMap { $0.toGroup }
            }
        } catch URLError.cancelled {
            print("Cancelled")
            throw SonosServiceError.cancelled
        }
        catch URLError.cannotConnectToHost {
            print("Can't connect")
            throw SonosServiceError.sonosSystemNotFound
        }
        catch {
            print(#function, error.localizedDescription)
            // Clear IP and try again.
            throw SonosServiceError.sonosSystemNotFound
        }
        
        return []
    }

    func getRoom(ipAddress: String) async -> [Room] {
        let arguments: [String: Any] = [:]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: arguments, endpoint: "ZoneGroupTopology") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
            let zones = XMLParserSonos().parseZones(xml: xmlString.unescaped)

            let mappedRooms = zones.flatMap { zoneGroup in
                zoneGroup.zoneGroupMembers.compactMap {
                    if !$0.invisible {
                        let components = URLComponents(string: $0.location)
                        if let ip = components?.host {
                            return Room(id: $0.UUID, ip: ip, name: $0.zoneName)
                        }
                    }
                    return nil
                }
            }

            return mappedRooms
        }
        return []
    }

    func removeAllTrackFromQueue(IP: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "RemoveAllTracksFromQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func removeTrackFromQueue(IP: String, index: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "ObjectID": "Q:0/\(index + 1)",
            "UpdateID": 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "RemoveTrackFromQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

//    func reorderQueue(IP: String) async {
//        let arguments: [String: Any] = [
//            "InstanceID": 0,
//            "StartingIndex": max(1,9),
//            "NumberOfTracks": 1,
//            "InsertBefore": max(1,1),
//            "UpdateID": 0
//        ]
//
//        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "ReorderTracksInQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
//            if (response as? HTTPURLResponse)?.statusCode != 200 {
//                print("Failed")
//            }
//        }
//    }

    func ungroup(IP: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "BecomeCoordinatorOfStandaloneGroup", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.log("Failed to ungroup")
        }
    }

    func group(IP: String, to coordinatorID: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "CurrentURI": "x-rincon:\(coordinatorID)",
            "CurrentURIMetaData": ""
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.log("Failed to group")
        }
    }


    func queue(song: String, IP: String, position: QueuePosition = .next) async {
        let enqueuedURIMetadata = """
        &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="10032020song%3a\(song)" restricted="true"&gt;&lt;dc:title&gt;Apple Music&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON52231_X_#Svc52231-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """
        var arguments: [String: Any] = [:]
        switch position {
        case .front:
            // MARK: Front
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-http:song%3a\(song).mp4?sid=204&amp;flags=8224&amp;sn=5",
                "EnqueuedURIMetaData": enqueuedURIMetadata,
                "DesiredFirstTrackNumberEnqueued": 1,
                "EnqueueAsNext": 1
            ]
        case .end:
            // MARK: End
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-http:song%3a\(song).mp4?sid=204&amp;flags=8224&amp;sn=5",
                "EnqueuedURIMetaData": enqueuedURIMetadata,
                "DesiredFirstTrackNumberEnqueued": 0,
                "EnqueueAsNext": 1
            ]
        case .next:
            // MARK: Next
            let position = await getCurrentTrack(ipAddress: IP)?.position ?? -1
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-http:song%3a\(song).mp4?sid=204&amp;flags=8224&amp;sn=5",
                "EnqueuedURIMetaData": enqueuedURIMetadata,
                "DesiredFirstTrackNumberEnqueued": position + 1,
                "EnqueueAsNext": 1
            ]
        }

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
                print(response)
            }
        }
    }

    func queueSpotifyPlaylist(ID: String, title: String, owner: String, IP: String) async {
        let URIMetadata = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="1006206cspotify%3aplaylist%3a\(ID)" restricted="true"><dc:title>\(title.xmlAllowedString)&#32;-&#32;playlist&#32;by&#32;\(owner.xmlAllowedString)&#32;|&#32;Spotify</dc:title><upnp:class>object.container.playlistContainer.#PlaylistView</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON3079_X_#Svc3079-0-Token</desc></item></DIDL-Lite>
        """
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": "x-rincon-cpcontainer:1006206cspotify%3aplaylist%3a\(ID)?sid=12&amp;flags=44&amp;sn=3",
            "EnqueuedURIMetaData": URIMetadata.escaped,
            "DesiredFirstTrackNumberEnqueued": 0,
            "EnqueueAsNext": 0
        ]

        print(URIMetadata.escaped)

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func queueSpotifyTrack(ID: String, IP: String, position: QueuePosition = .next) async {
        let metaData = "track:\(ID)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped

        let URIMetadata = """
        &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="10032020spotify%3a\(metaData)" restricted="true"&gt;&lt;dc:title&gt;Dance&amp;#32;The&amp;#32;Night&amp;#32;-&amp;#32;From&amp;#32;Barbie&amp;#32;The&amp;#32;Album&amp;#32;-&amp;#32;song&amp;#32;and&amp;#32;lyrics&amp;#32;by&amp;#32;Dua&amp;#32;Lipa&amp;#32;|&amp;#32;Spotify&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON3079_X_#Svc3079-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """

        let test = "spotify:track:\(ID)?sid=9&flags=8224&sn=7".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped

        var arguments: [String: Any] = [:]
        switch position {
        case .front:
            // MARK: Front
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-spotify:" + test,
                "EnqueuedURIMetaData": URIMetadata,
                "DesiredFirstTrackNumberEnqueued": 1,
                "EnqueueAsNext": 1
            ]
        case .end:
            // MARK: End
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-spotify:" + test,
                "EnqueuedURIMetaData": URIMetadata,
                "DesiredFirstTrackNumberEnqueued": 0,
                "EnqueueAsNext": 1
            ]
        case .next:
            // MARK: Next
            let position = await getCurrentTrack(ipAddress: IP)?.position ?? -1
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-spotify:" + test,
                "EnqueuedURIMetaData": URIMetadata,
                "DesiredFirstTrackNumberEnqueued": position + 1,
                "EnqueueAsNext": 1
            ]
        }

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            } else {
                print("Success", (response as? HTTPURLResponse)?.statusCode)
            }
        }
    }

    func queueSpotifyAlbum(ID: String, IP: String, position: QueuePosition = .next) async {
        let URIMetadata = """
        &lt;DIDL-Lite&#32;xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot;&#32;xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;&#32;xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&#32;xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item&#32;id=&quot;1004206cspotify%3aalbum%3a7fJJK56U9fHixgO0HQkhtI&quot;&#32;restricted=&quot;true&quot;&gt;&lt;dc:title&gt;Future&amp;#32;Nostalgia&amp;#32;-&amp;#32;Album&amp;#32;by&amp;#32;Dua&amp;#32;Lipa&amp;#32;|&amp;#32;Spotify&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc&#32;id=&quot;cdudn&quot;&#32;nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;SA_RINCON3079_X_#Svc3079-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """

        let trackURI = "x-rincon-cpcontainer:1004206cspotify:album:\(ID)?sid=9&flags=8300&sn=7".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped

        var arguments: [String: Any] = [:]
        switch position {
        case .front:
            // MARK: Front
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-spotify:" + trackURI,
                "EnqueuedURIMetaData": URIMetadata.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped,
                "DesiredFirstTrackNumberEnqueued": 1,
                "EnqueueAsNext": 1
            ]
        case .end:
            // MARK: End
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-sonos-spotify:" + trackURI,
                "EnqueuedURIMetaData": URIMetadata.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped,
                "DesiredFirstTrackNumberEnqueued": 0,
                "EnqueueAsNext": 1
            ]
        case .next:
            // MARK: Next
            let position = await getCurrentTrack(ipAddress: IP)?.position ?? -1
            arguments = [
                "InstanceID": 0,
                "EnqueuedURI": "x-rincon-cpcontainer:1004206cspotify%3aalbum%3a\(ID)?sid=12&amp;flags=8300&amp;sn=3",
                "EnqueuedURIMetaData": URIMetadata,
                "DesiredFirstTrackNumberEnqueued": position + 1,
                "EnqueueAsNext": 1
            ]
        }

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            } else {
                print("Success", (response as? HTTPURLResponse)?.statusCode)
            }
        }

    }

    func getCurrentTransportActions(IP: String) async -> AvailableActions? {
        let arguments: [String: Any] = [
            "InstanceID": 0
        ]

        if let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetCurrentTransportActions", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                let xmlString = String(data: data, encoding: .utf8)!
                guard let transportActions = XMLParserSonos().parseGetCurrentTransportActions(xml: xmlString) else {
                    return nil
                }
                print(transportActions)
            }
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                print("Success")
            }
        }
        return AvailableActions(arrayLiteral: [.next, .play])
    }

    func getQueue(IP: String) async -> [Track] {
        let arguments: [String: Any] = [
            "ObjectID": "Q:0",
            "BrowseFlag": "BrowseDirectChildren",
            "Filter": "*",
            "StartingIndex": 0,
            "RequestedCount": 0,
            "SortCriteria": ""
        ]

        if let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }

            guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
            print(xmlString)

            return XMLParserSonos().parseQueue(xml: xmlString)
        }
        return []
    }
    
    func seek(trackNumber: Int, IP: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Unit": "TRACK_NR",
            "Target": trackNumber,
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "Seek", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func setAVTransport(IP: String, ID: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "CurrentURI": "x-rincon-queue:\(ID)#0",
            "CurrentURIMetaData": "",
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func getHouseHoldID(for IP: String) async -> String {
        if let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetZoneGroupAttributes", arguments: [:], endpoint: "ZoneGroupTopology") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return "" }
            let houseID = XMLParserSonos().parseHouseID(xml: xmlString)
            return houseID
        }

        return ""
    }

    
    func createSoapRequest(ip: String, action: String, arguments: [String: Any], endpoint: String) -> URLRequest? {
        let xmlString = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope
                xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                <s:Body>
                    <u:\(action) xmlns:u="urn:schemas-upnp-org:service:\(endpoint.components(separatedBy: "/").last!):1">
            """
            + arguments.map({ "<\( $0.key )>\( $0.value )</\( $0.key )>" }).joined()
            + """
                    </u:\(action)>
                </s:Body>
            </s:Envelope>
        """

        guard let url = URL(string: "http://\(ip):1400/\(endpoint)/Control") else { return nil }
        var request = URLRequest(url: url)
        request.addValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.addValue("\"urn:schemas-upnp-org:service:\(endpoint.components(separatedBy: "/").last!):1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpMethod = "POST"
        request.httpBody = xmlString.data(using: .utf8)
        return request
    }

    @discardableResult func sendSoapRequest(ip: String, action: String, arguments: [String: Any], endpoint: String) async throws -> (Data, URLResponse)? {
        guard let request = createSoapRequest(ip: ip, action: action, arguments: arguments, endpoint: endpoint) else {
            return nil
        }
        return try await session.data(for: request)
    }
}

