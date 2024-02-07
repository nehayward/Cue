import Foundation
import OSLog
import Network

/// `SonosAPI` provides a set of functionalities to interact with Sonos devices over the network.
/// It handles tasks like setting volume, getting track info, and other control actions.
final class SonosAPI: NSObject {
    private let logger: Logger = Logger(subsystem: "com.sonos.nick", category: "SonosAPI")
    private lazy var session: URLSession = privateSession
    private lazy var insecure: URLSession = insecureSession

    private lazy var xmlParser = XMLParserSonos()
    private lazy var decoder = JSONDecoder()
    private lazy var encoder = JSONEncoder()

    private lazy var privateSession: URLSession = {
        let configuration: URLSessionConfiguration = .default
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 3
        return URLSession(configuration: configuration)
    }()

    private lazy var insecureSession: URLSession = {
        let configuration: URLSessionConfiguration = .default
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 3
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
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

    func getGroupMute(IP: String) async -> Bool? {
        let arguments: [String: Any] = [
            "InstanceID": 0
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetGroupMute", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else {
            logger.error("\(IP) Failed to \(#function)")
            return nil
        }
        
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.error("\(IP) Failed to \(#function)")
        }
        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseGetGroupMute(xml: xml)
    }

    func getRoomMute(IP: String) async -> Bool? {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master"
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetMute", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            logger.error("\(IP) Failed to \(#function)")
            return nil
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseGetRoomMute(xml: xml)
    }

    func setRoomMute(IP: String, mute: Bool) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
            "DesiredMute": mute ? 1 : 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetMute", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                logger.error("\(IP) Failed to \(#function)")
            }
        }
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
        let volume = try xmlParser.parseVolume(xml: xml)
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
        let volume = try xmlParser.parseGroupVolume(xml: xml)
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

    @MainActor
    func getCurrentTrack(ipAddress: String) async -> Track? {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetPositionInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else  {
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        let trackInfo = xmlParser.parsePositionInfo(xml: xml.unescaped, IP: ipAddress)
        SonosLogInformation.shared.log(name: "\(ipAddress)_track.txt", xml.unescaped)
        return trackInfo
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
            let playbackInfo = xmlParser.parsePlaybackInfo(xml: xmlString)
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
        return xmlParser.parsePlaybackMode(xml) ?? .normal
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
            let isTVMode = xmlParser.parseMediaInfo(xml: xmlString)
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
            guard let (data, _) = try await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: [:], endpoint: "ZoneGroupTopology") else { return [] }
            guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
            SonosLogInformation.shared.log(name: "Groups.txt", xmlString.unescaped)
            let zones = xmlParser.parseZones(xml: xmlString.unescaped)
            return zones.compactMap { $0.toGroup }
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
    }

    func system(for IP: String) async throws -> System {
        do {
            guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetZoneGroupState", arguments: [:], endpoint: "ZoneGroupTopology") else  {
                throw SonosAPIError.deviceNotFound
            }
            guard let xmlString = String(data: data, encoding: .utf8) else { throw SonosAPIError.deviceNotFound }

            SonosLogInformation.shared.log(name: "Groups.txt", xmlString.unescaped)
            let zones = xmlParser.parseZones(xml: xmlString.unescaped)
            let mappedZones =  zones.compactMap { $0.toGroup }
            let vanishedDevices = xmlParser.parseVanishedDevices(xml: xmlString.unescaped)

            return System(zones: mappedZones, vanished: vanishedDevices, id: "")

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
    }

    func getRoom(ipAddress: String) async -> [Room] {
        let arguments: [String: Any] = [:]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: arguments, endpoint: "ZoneGroupTopology") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
            let zones = xmlParser.parseZones(xml: xmlString.unescaped)

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

    func reorderQueue(group: GroupRoom, from: Int, to: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "StartingIndex": from,
            "NumberOfTracks": 1,
            "InsertBefore": to,
            "UpdateID": 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: group.ip, action: "ReorderTracksInQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

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
        var arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": "x-sonos-http:song%3a\(song).mp4?sid=204&amp;flags=8224&amp;sn=5",
            "EnqueuedURIMetaData": enqueuedURIMetadata,
            "DesiredFirstTrackNumberEnqueued": 1,
            "EnqueueAsNext": 0
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

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
                print(response)
            }
        }
    }

    func queueSpotifyPlaylist(ID: String, IP: String) async {
        let URIMetadata = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="1006206cspotify%3aplaylist%3a\(ID)" restricted="true"><dc:title>Clic&#32;-&#32;playlist&#32;by&#32;Clic&#32;|&#32;Spotify</dc:title><upnp:class>object.container.playlistContainer.#PlaylistView</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON3079_X_#Svc3079-0-Token</desc></item></DIDL-Lite>
        """
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": "x-rincon-cpcontainer:1006206cspotify%3aplaylist%3a\(ID)?sid=12&amp;flags=44&amp;sn=3",
            "EnqueuedURIMetaData": URIMetadata.escaped,
            "DesiredFirstTrackNumberEnqueued": 0,
            "EnqueueAsNext": 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            print("Failed:", response)
        }
    }

    func queueSpotifyTrack(ID: String, IP: String, position: QueuePosition = .next) async {
        let metaData = "track:\(ID)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped

        let URIMetadata = """
        &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="10032020spotify%3a\(metaData)" restricted="true"&gt;&lt;dc:title&gt;Dance&amp;#32;The&amp;#32;Night&amp;#32;-&amp;#32;From&amp;#32;Barbie&amp;#32;The&amp;#32;Album&amp;#32;-&amp;#32;song&amp;#32;and&amp;#32;lyrics&amp;#32;by&amp;#32;Dua&amp;#32;Lipa&amp;#32;|&amp;#32;Spotify&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON3079_X_#Svc3079-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """

        let URI = "x-sonos-spotify:" + "spotify:track:\(ID)?sid=9&flags=8224&sn=7".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.escaped

        var arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": URI,
            "EnqueuedURIMetaData": URIMetadata,
            "DesiredFirstTrackNumberEnqueued": 1,
            "EnqueueAsNext": 0
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

        let albumURI = "x-rincon-cpcontainer:1004206cspotify%3aalbum%3a\(ID)?sid=12&amp;flags=8300&amp;sn=3"

        var arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": albumURI,
            "EnqueuedURIMetaData": URIMetadata,
            "DesiredFirstTrackNumberEnqueued": 1,
            "EnqueueAsNext": 1
        ]

        switch position {
        case .front: break
        case .end:
            arguments["DesiredFirstTrackNumberEnqueued"] = 0
        case .now:
            let index = await getCurrentTrack(ipAddress: IP)?.position ?? 1
            arguments["DesiredFirstTrackNumberEnqueued"] = index
            arguments["EnqueueAsNext"] = 0
        case .next:
            let index = await getCurrentTrack(ipAddress: IP)?.position ?? 1
            arguments["DesiredFirstTrackNumberEnqueued"] = index + 1
            arguments["EnqueueAsNext"] = 1
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
                guard let transportActions = xmlParser.parseGetCurrentTransportActions(xml: xmlString) else {
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
            return await xmlParser.parseQueue(IP: IP, xml: xmlString)
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


    /// Seek
    /// - Parameters:
    ///   - delta: Time in Seconds
    ///   - IP: IP of Sonos
    func seek(to delta: Int, IP: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Unit": "TIME_DELTA",
            "Target": "\(delta < 0 ? "-": "")00:00:\(abs(delta))",
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "Seek", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }


    /// Seek to time in milliseconds
    /// - Parameters:
    ///   - time: Time in milliseconds
    ///   - IP: Group IP
    func seek(to time: TimeInterval, IP: String) async {
        // MARK: Convert milliseconds to time.
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Unit": "REL_TIME",
            "Target": convertMillisecondsToHoursMinutesSeconds(Int(time)),
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "Seek", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    private func convertMillisecondsToHoursMinutesSeconds(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        // Format string to "HH:mm:ss"
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
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
            let houseID = xmlParser.parseHouseID(xml: xmlString)
            return houseID
        }

        return ""
    }

    func getFavorites(for IP: String) async -> FavoritesList? {
        let houseHoldID = await getHouseHoldID(for: IP)
        guard let url = URL(string: "https://\(IP):1443/api/v1/households/\(houseHoldID)/favorites") else { return nil }
        var request = URLRequest(url: url)
        request.addValue("00aa27d9-e053-4de9-864a-09eeda033099", forHTTPHeaderField: "X-Sonos-Api-Key")
        request.httpMethod = "GET"

        guard let (data, response) = try? await insecure.data(for: request), let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            logger.error("\(IP) Failed to \(#function)")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        print(xml)
        guard let favoriteList = try? decoder.decode(FavoritesList.self, from: data) else { return nil }
        print(favoriteList)
        return favoriteList
    }
    

    func playFavorite(on group: GroupRoom, favoriteID: String) async {
        guard let url = URL(string: "https://\(group.ip):1443/api/v1/groups/\(group.id)/favorites") else { return }
        var request = URLRequest(url: url)
        request.addValue("00aa27d9-e053-4de9-864a-09eeda033099", forHTTPHeaderField: "X-Sonos-Api-Key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"

        struct Favorite: Codable {
            let favoriteId: String
        }

        let favorite = Favorite(favoriteId: favoriteID)
        request.httpBody = try? encoder.encode(favorite)

        print(String(decoding: request.httpBody!, as: UTF8.self))

        guard let (data, response) = try? await insecure.data(for: request) else {
            logger.error("\(group.nameWithCount) (\(group.ip)) Failed to \(#function)")
            return
        }

        if let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode {
            let xml = String(decoding: data, as: UTF8.self)
            print(xml)
            logger.error("\(group.nameWithCount) Failed to \(#function)")
            return
        }


//        guard let favoriteList = try? decoder.decode(FavoritesList.self, from: data) else { return nil }
//        print(favoriteList)
//        return favoriteList
    }

    func favoriteArtwork(on favorite: Favorite, group: GroupRoom) -> URL? {
        if let sonosAlbumArtURL = URL(string: "http://\(group.ip):1400\(favorite.imageUrl.unescaped)") {
            print(sonosAlbumArtURL)
            return sonosAlbumArtURL
        }

        print(favorite.imageUrl)
        return URL(string: favorite.imageUrl)
    }

    func deleteFavorite(IP: String, itemID: String) async{
        let arguments: [String: Any] = [
            "ObjectID": "FV:2/\(itemID)",
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "DestroyObject", arguments: arguments, endpoint: "MediaServer/ContentDirectory") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
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

extension SonosAPI: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        //Trust the certificate even if not valid
        let urlCredential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
        completionHandler(.useCredential, urlCredential)
    }
}

