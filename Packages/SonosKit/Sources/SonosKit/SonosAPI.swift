import Foundation
import OSLog
import Network
import Defaults

/// `SonosAPI` provides a set of functionalities to interact with Sonos devices over the network.
/// It handles tasks like setting volume, getting track info, and other control actions.
final class SonosAPI: NSObject {
    typealias OrderedKeys = [(key: String, value: Any)]
    private let logger: Logger = Logger(subsystem: "com.sonos.nick", category: "SonosAPI")
    lazy var session: URLSession = privateSession
    private lazy var queueSession: URLSession = queueSessionConfig

    var xmlParser = XMLParserSonos()
    lazy var decoder = JSONDecoder()
    lazy var encoder = JSONEncoder()

    private lazy var privateSession: URLSession = {
        let configuration: URLSessionConfiguration = .default
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private lazy var queueSessionConfig: URLSession = {
        let configuration: URLSessionConfiguration = .default
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()
    
    deinit {
        // Invalidate URLSession instances to prevent memory leaks
        session.invalidateAndCancel()
        queueSession.invalidateAndCancel()
    }
    
    private static var spotifyLocal: String {
        return Locale.current.region?.identifier ?? "US" == "US" ? "3079" : "2311"
    }

    func setVolume(ipAddress: String, volume: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master"),
            ("DesiredVolume", volume)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "SetVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }
    
    func getGroupMute(IP: String) async -> Bool? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetGroupMute", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else {
            return nil
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.error("\(IP): Failed to \(#function)")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseMute(xml: xml)
    }

    func getRoomMute(IP: String) async -> Bool? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetMute", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            return nil
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseMute(xml: xml)
    }

    func setRoomMute(IP: String, mute: Bool) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master"),
            ("DesiredMute", mute ? 1 : 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetMute", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.error("\(IP) Failed to \(#function)")
        }
    }

    func setGroupMute(IP: String, mute: Bool) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("DesiredMute", mute ? 1 : 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetGroupMute", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else { return }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.error("\(IP) Failed to \(#function)")
        }
    }

    func setRelativeVolume(ipAddress: String, volume: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master"),
            ("Adjustment", volume)
        ]

        try? await sendSoapRequest(ip: ipAddress, action: "SetRelativeVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl")
    }

    func setRelativeGroupVolume(ipAddress: String, volume: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Adjustment", volume)
        ]

        try? await sendSoapRequest(ip: ipAddress, action: "SetRelativeGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl")
    }

    func getVolume(ipAddress: String) async throws -> Double {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master")
        ]

        guard let (data, _) = try await sendSoapRequest(ip: ipAddress, action: "GetVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            throw SonosAPIError.requestBuild
        }

        let xml = String(decoding: data, as: UTF8.self)
        let volume = try xmlParser.parseVolume(xml: xml)
        return Double(volume)
    }

    @discardableResult func getGroupVolume(ipAddress: String) async throws -> Double {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else {
            throw SonosAPIError.requestBuild
        }
        
        let xml = String(decoding: data, as: UTF8.self)
        let volume = try xmlParser.parseVolume(xml: xml)
        return Double(volume)
    }

    func setGroupVolume(IP: String, volume: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("DesiredVolume", volume)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else { return }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.error("\(IP) Failed to \(#function)")
        }
    }

    func snapshotGroupVolume(ipAddress: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "SnapshotGroupVolume", arguments: arguments, endpoint: "MediaRenderer/GroupRenderingControl") else { return }
        let xml = String(decoding: data, as: UTF8.self)
        print(xml)
    }

    @MainActor
    func getCurrentTrack(ipAddress: String, prioritizedAlbumArtIP: String? = nil) async -> Track? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetPositionInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        let trackInfo = xmlParser.parsePositionInfo(xml: xml.unescaped, IP: ipAddress, preferredIPForTrackAlbumArt: prioritizedAlbumArtIP)
        SonosLogInformation.shared.log(name: "\(ipAddress)_track.txt", xml.unescaped)
        return trackInfo
    }
    
    @MainActor
    func getCurrentQueueIndex(ipAddress: String, prioritizedAlbumArtIP: String? = nil) async -> Int {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetPositionInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return 0
        }

        let xml = String(decoding: data, as: UTF8.self)
        let trackInfo = xmlParser.parsePositionInfo(xml: xml.unescaped, IP: ipAddress, preferredIPForTrackAlbumArt: prioritizedAlbumArtIP)
        SonosLogInformation.shared.log(name: "\(ipAddress)_track.txt", xml.unescaped)
        var position = (trackInfo?.position ?? 0)
        position = position == 1 ? 0 : position
        return position
    }

    func pause(ipAddress: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Pause", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func play(ipAddress: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Speed", 1)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Play", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
            print(response)
        }
    }

    func next(ipAddress: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Speed", 1)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Next", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func previous(ipAddress: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "Previous", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func isPlaying(ipAddress: String) async -> PlaybackStatus {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetTransportInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return .transitioning
        }

        let xml = String(decoding: data, as: UTF8.self)
        let playbackInfo = xmlParser.parsePlaybackInfo(xml: xml)
        return playbackInfo
    }

    public func playMode(_ IP: String) async -> PlayMode {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetTransportSettings", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return .normal
        }
        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parsePlaybackMode(xml) ?? .normal
    }

    public func setPlayMode(_ IP: String, playMode: PlayMode) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("NewPlayMode", playMode.sonosMode.uppercased())
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "SetPlayMode", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            print("Failed")
            return
        }

        let xml = String(decoding: data, as: UTF8.self)
        print(xml)
    }

    func mediaInfo(ipAddress: String) async -> PlaybackMediaInfo? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetMediaInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseMediaInfo(xml: xml)
    }


//    func batteryLevel(IP: String) {
//        guard let url = URL(string: "http://\(IP):1400/status/batterystatus") else { return }
//        let request = URLRequest(url: url)
//    }

    func getGroups(ipAddress: String) async throws -> [GroupRoom] {
        do {
            guard let (data, _) = try await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: [], endpoint: "ZoneGroupTopology") else {
                return []
            }
            let xml = String(decoding: data, as: UTF8.self)
            SonosLogInformation.shared.log(name: "Groups.txt", xml.unescaped)
            let zones = xmlParser.parseZones(xml: xml.unescaped)
            let vanishedZones = xmlParser.parseVanishedDevices(xml: xml.unescaped).compactMap { $0.toGroup }
            let groups = zones.compactMap { $0.toGroup }
            if (groups + vanishedZones).isEmpty {
                throw SonosServiceError.parseError(xml)
            }
            return groups + vanishedZones
        } catch URLError.cannotConnectToHost {
            print("Can't connect")
            throw SonosServiceError.sonosSystemNotFound
        } catch SonosServiceError.parseError(let xml) {
            throw SonosServiceError.parseError(xml)
        } catch {
            print(#function, error.localizedDescription)
            // Clear IP and try again.
            throw SonosServiceError.sonosSystemNotFound
        }
    }

    func system(for IP: String) async throws -> System {
        do {
            guard let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetZoneGroupState", arguments: [], endpoint: "ZoneGroupTopology") else  {
                throw SonosAPIError.deviceNotFound
            }
            guard let xmlString = String(data: data, encoding: .utf8) else { throw SonosAPIError.deviceNotFound }

            SonosLogInformation.shared.log(name: "Groups.txt", xmlString.unescaped)
            let zones = xmlParser.parseZones(xml: xmlString.unescaped)
            let mappedZones =  zones.compactMap { $0.toGroup }
            let vanishedDevices = xmlParser.parseVanishedDevices(xml: xmlString.unescaped)

            return System(zones: mappedZones, vanished: vanishedDevices, id: "")

        } catch URLError.cannotConnectToHost {
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
        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: [], endpoint: "ZoneGroupTopology") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
            let zones = xmlParser.parseZones(xml: xmlString.unescaped)

            let mappedRooms = zones.flatMap { zoneGroup in
                zoneGroup.members.compactMap {
                    if !$0.invisible {
                        let components = URLComponents(string: $0.location)
                        if let ip = components?.host {
                            return Room(id: $0.UUID, ip: ip, name: $0.zoneName, channelMap: $0.channelMap, satChannelMap: $0.satChannelMap)
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
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master")
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "RemoveAllTracksFromQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func removeTrackFromQueue(IP: String, index: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("ObjectID", "Q:0/\(index)"),
            ("UpdateID", 0)
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "RemoveTrackFromQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func reorderQueue(group: GroupRoom, from: Int, to: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("StartingIndex", from),
            ("NumberOfTracks", 1),
            ("InsertBefore", to),
            ("UpdateID", 0)
        ]

        if let (_, response) = try? await sendSoapRequest(ip: group.ip, action: "ReorderTracksInQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func ungroup(IP: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "BecomeCoordinatorOfStandaloneGroup", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.log("Failed to ungroup")
        }
    }

    func group(IP: String, to coordinatorID: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CurrentURI", "x-rincon:\(coordinatorID)"),
            ("CurrentURIMetaData", "")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            logger.log("Failed to group")
        }
    }
    
    func queueSpotifyArtistTopTracks(ID: String, IP: String) async {
        let URIMetadata = """
        &lt;DIDL-Lite&#32;
                        xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot;&#32;
                        xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;&#32;
                        xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&#32;
                        xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item&#32;id=&quot;1006206cspotify%3aartistTopTracks%3a\(ID)&quot;&#32;restricted=&quot;true&quot;&gt;&lt;dc:title&gt;Spotify&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;&lt;desc&#32;id=&quot;cdudn&quot;&#32;nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;SA_RINCON\(Self.spotifyLocal)_X_#Svc\(Self.spotifyLocal)-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """
        let URI = "x-rincon-cpcontainer:000e206cspotify%3aartistTopTracks%3a\(ID)"
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EnqueuedURI", URI),
            ("EnqueuedURIMetaData", URIMetadata),
            ("DesiredFirstTrackNumberEnqueued", 0),
            ("EnqueueAsNext", 0)
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("Failed:", response)
                return
            }
        }
    }

    func queuePlayable(playableContent: PlayableContent, IP: String, position: QueuePosition = .next) async throws {
        var desiredFirstTrackNumberEnqueued: (String, Any) = ("DesiredFirstTrackNumberEnqueued", 1)
        
        switch position {
        case .front: break
        case .replace:
            break
        case .end:
            desiredFirstTrackNumberEnqueued.1 = 0
        case .now, .next:
            let index = await getCurrentTrack(ipAddress: IP)?.position ?? 1
            desiredFirstTrackNumberEnqueued.1  = index + 1
        }
            
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EnqueuedURI", playableContent.uri),
            ("EnqueuedURIMetaData", playableContent.URIMetadata),
            desiredFirstTrackNumberEnqueued,
            ("EnqueueAsNext", 1)
        ]

        guard let (data, response) = try await sendQueueSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            throw SonosServiceError.timeout
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            let body = String(decoding: data, as: UTF8.self)
            let errorCode = extractErrorCode(from: body) // 800 not authorized
            print("Error (\(errorCode): \(body)")
            throw SonosServiceError.serviceUnavailable
        }
    }
    
    func extractErrorCode(from xml: String) -> String? {
        let pattern = "<errorCode>(\\d+)</errorCode>"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        if let match = regex?.firstMatch(in: xml, options: [], range: range),
           let codeRange = Range(match.range(at: 1), in: xml) {
            return String(xml[codeRange])
        }
        return nil
    }

    func replaceQueue(playableContent: PlayableContent, IP: String, index: Int = 0) async throws {
        let arguments: OrderedKeys = [
            ("QueueID", 0),
            ("UpdateID", 0),
            ("ContainerURI", ""),
            ("ContainerMetaData", ""),
            ("CurrentTrackIndex", 0),
            ("NewCurrentTrackIndices", index),
            ("NumberOfURIs", 1),
            ("EnqueuedURIsAndMetaData", playableContent.URIAndURIMetada)
        ]

        guard let (_, response) = try await sendSoapRequest(ip: IP, action: "ReplaceAllTracks", arguments: arguments, endpoint: "MediaRenderer/Queue") else {
            throw SonosServiceError.timeout
        }

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
            print("Failed", statusCode)
            throw SonosServiceError.serviceUnavailable
        }
    }

    func startRadio(playableContent: PlayableContent, IP: String) async throws {
        guard let radioURI = playableContent.uriRadio, let URIMetadataRadio = playableContent.URIMetadataRadio else { return }

        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CurrentURI", radioURI),
            ("CurrentURIMetaData", URIMetadataRadio)
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
                throw SonosServiceError.serviceUnavailable
            }
        }
    }

    func getCurrentTransportActions(IP: String) async -> AvailableActions? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetCurrentTransportActions", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return nil
        }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        guard let transportActions = xmlParser.parseGetCurrentTransportActions(xml: xml) else {
            return nil
        }
        return transportActions
    }

    func getQueue(IP: String, prioritizedAlbumArtIP: String? = nil) async -> [PlayableContent] {
        let arguments: OrderedKeys = [
            ("ObjectID", "Q:0"),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 0),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        let queue = xmlParser.parseQueue(IP: IP, xml: xml, preferredIPForTrackAlbumArt: prioritizedAlbumArtIP)
        SonosLogInformation.shared.log(name: "\(IP)_queue.txt", xml.unescaped)
        return queue
    }
    
    func getQueue(IP: String, startingIndex: Int, total: Int, priorityIP: String? = nil) async -> [PlayableContent] {
        let arguments: OrderedKeys = [
            ("ObjectID", "Q:0"),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", startingIndex),
            ("RequestedCount", total),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        let queue = xmlParser.parseQueue(IP: IP, xml: xml, preferredIPForTrackAlbumArt: priorityIP)
        return queue
    }

    func getQueueCount(IP: String) async -> Int? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetMediaInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        if let value = try? xmlParser.parseValue(xml: xml, named: "NrTracks"), let queueTotal = Int(value) {
            return queueTotal
        }
        return nil
    }

    func seek(trackNumber: Int, IP: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Unit", "TRACK_NR"),
            ("Target", trackNumber)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "Seek", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func seek(to delta: Int, IP: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Unit", "TIME_DELTA"),
            ("Target", "\(delta < 0 ? "-": "")00:00:\(abs(delta))")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "Seek", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func seek(to time: TimeInterval, IP: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Unit", "REL_TIME"),
            ("Target", convertMillisecondsToHoursMinutesSeconds(Int(time)))
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

        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    func setAVTransport(IP: String, ID: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CurrentURI", "x-rincon-queue:\(ID)#0"),
            ("CurrentURIMetaData", "")
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func setAVTransportContent(playableContent: PlayableContent, IP: String) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CurrentURI", playableContent.uri),
            ("CurrentURIMetaData", playableContent.URIMetadata)
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
                throw SonosServiceError.serviceUnavailable
            }
        }
    }

    func crossfade(IP: String) async -> Bool? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetCrossfadeMode", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return nil
        }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        guard let isCrossfaded = xmlParser.parseGetCrossfade(xml: xml) else {
            return nil
        }
        return isCrossfaded
    }
    func setCrossfade(IP: String, enabled: Bool) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CrossfadeMode", enabled ? 1 : 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetCrossfadeMode", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed \(#function)")
        }
    }

    func setSleepTimer(IP: String, duration: Duration) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("NewSleepTimerDuration", duration.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2))))
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "ConfigureSleepTimer", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func getSleepTimer(IP: String) async -> Date? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetRemainingSleepTimerDuration", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return nil
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        guard let timeEnds = xmlParser.parseSleepTimer(xml: xml) else {
            return nil
        }
        return timeEnds
    }

    func getSupportsOutputFixed(IP: String) async -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetSupportsOutputFixed", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if (response as? HTTPURLResponse)?.statusCode != 200 { return false }
        let xml = String(decoding: data, as: UTF8.self)
        guard let result = try? xmlParser.parseValue(xml: xml, named: "CurrentSupportsFixed") else { return false }
        return result == "1"
    }

    func getOutputFixed(IP: String) async -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetOutputFixed", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if (response as? HTTPURLResponse)?.statusCode != 200 { return false }
        let xml = String(decoding: data, as: UTF8.self)
        guard let result = try? xmlParser.parseValue(xml: xml, named: "CurrentFixed") else { return false }
        return result == "1"
    }

    func stopSleepTimer(IP: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("NewSleepTimerDuration", "")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "ConfigureSleepTimer", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func getHouseHoldID(for IP: String) async -> String {
        if let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetZoneGroupAttributes", arguments: [], endpoint: "ZoneGroupTopology") {
            let xmlString = String(decoding: data, as: UTF8.self)
            let houseID = xmlParser.parseHouseID(xml: xmlString)
            return houseID.components(separatedBy: ".").first ?? ""
        }

        return ""
    }
    
    func switchToLineIn(IP: String, ID: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CurrentURI", "x-rincon-stream:\(ID)"),
            ("CurrentURIMetaData", "")
        ]
        
        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    // MARK: - Favorites
    func getFavorites(for IP: String) async -> [PlayableContent] {
        let objectID = "FV:2"
        let arguments: OrderedKeys = [
            ("ObjectID", objectID),
            ("BrowseFlag", "BrowseDirectChildren"),
            ("Filter", "*"),
            ("StartingIndex", 0),
            ("RequestedCount", 0),
            ("SortCriteria", "")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "Browse", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseFavorites(IP: IP, xml: xml)
    }
    
    func deleteFavorite(IP: String, itemID: String) async {
        let arguments: OrderedKeys = [
            ("ObjectID", "FV:2/\(itemID)")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "DestroyObject", arguments: arguments, endpoint: "MediaServer/ContentDirectory") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func deviceInfo(IP: String) async -> DeviceInfo? {
        guard let url = URL(string: "http://\(IP):1400/info") else { return nil }
        let request = URLRequest(url: url)
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
        
        do {
            let discoveryInfo = try decoder.decode(DiscoveryInfo.self, from: data)
            return discoveryInfo.device
        } catch {
            print(String(decoding: data, as: UTF8.self))
            print("Error decoding JSON: \(error)")
        }
        
        return nil
    }

    func createSoapRequest(ip: String, action: String, arguments: [(key: String, value: Any)], endpoint: String) -> URLRequest? {
        var schemas = "schemas-upnp-org"
        let service = "\(endpoint.components(separatedBy: "/").last!)"
        if service == "Queue" {
            schemas = "schemas-sonos-com"
        }
        
        let urn = "urn:\(schemas):service:\(service):1"
        
        let xmlString = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope
                xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                <s:Body>
                    <u:\(action) xmlns:u="\(urn)">
            """
        + arguments.map({ ($0.value as? String)?.isEmpty ?? false ? "<\( $0.key )/>" :  "<\( $0.key )>\( $0.value )</\( $0.key )>" }).joined()
            + """
                    </u:\(action)>
                </s:Body>
            </s:Envelope>
        """

        guard let url = URL(string: "http://\(ip):1400/\(endpoint)/Control") else { return nil }
        var request = URLRequest(url: url)
        request.addValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.addValue("\"\(urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpMethod = "POST"
        request.httpBody = xmlString.data(using: .utf8)
        return request
    }

    @discardableResult func sendSoapRequest(ip: String, action: String, arguments: [(key: String, value: Any)], endpoint: String) async throws -> (Data, URLResponse)? {
        guard let request = createSoapRequest(ip: ip, action: action, arguments: arguments, endpoint: endpoint) else {
            return nil
        }
        do {
            let response = try await session.data(for: request)
            return response
        } catch URLError.cancelled {
            // MARK: Add Back for Debug
//            var body = ""
//            if let httpBody = request.httpBody {
//                body = String(decoding: httpBody, as: UTF8.self)
//            }
//            print("Cancelled:", request, body)
        } catch {
            logger.error("\(request) Failed to \(#function)")
            print(request, error.localizedDescription)
            throw error
        }
        return nil
    }
    
    @discardableResult func sendQueueSoapRequest(ip: String, action: String, arguments: [(key: String, value: Any)], endpoint: String) async throws -> (Data, URLResponse)? {
        guard let request = createSoapRequest(ip: ip, action: action, arguments: arguments, endpoint: endpoint) else {
            return nil
        }
        do {
            let response = try await queueSession.data(for: request)
            return response
        } catch URLError.cancelled {
            // MARK: Add Back for Debug
//            var body = ""
//            if let httpBody = request.httpBody {
//                body = String(decoding: httpBody, as: UTF8.self)
//            }
//            print("Cancelled:", request, body)
        } catch {
            logger.error("\(request) Failed to \(#function)")
            print(request, error.localizedDescription)
            throw error
        }
        return nil
    }
}

extension SonosAPI: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        //Trust the certificate even if not valid
        let urlCredential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
        completionHandler(.useCredential, urlCredential)
    }
}

