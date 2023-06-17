import Foundation

class SonosAPI {

    func subscribe(ip: String, deviceIP: String) {
        
        let url = URL(string: "http://\(ip):1400/MediaRenderer/RenderingControl/Event")!
        let callbackURL = "http://\(deviceIP):9094"
        let headers = [
            "CALLBACK": "<\(callbackURL)>",
            "NT": "upnp:event",
            "TIMEOUT": "Second-300"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.allHTTPHeaderFields = headers

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error subscribing: \(error)")
                return
            }
            if let response = response as? HTTPURLResponse {
                print("Subscription response: \(response.statusCode)")
            }
        }
        task.resume()
    }

    func monitorZones(ip: String, deviceIP: String) async -> String {
        let url = URL(string: "http://\(ip):1400/MediaRenderer/RenderingControl/Event")!
        let callbackURL = "http://\(deviceIP):9094"
        let headers = [
            "CALLBACK": "<\(callbackURL)>",
            "NT": "upnp:event",
            "TIMEOUT": "Second-300"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.allHTTPHeaderFields = headers

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return "" }
        print(String(data: data, encoding: .utf8))
        return ""
    }

    func setVolume(ipAddress: String, volume: Int) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
            "DesiredVolume": volume
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "SetVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") {
//            if let error = response. {
//                print("Error getting current track: \(error.localizedDescription)")
//                return
//            }
//            guard let data = data else { return }
            print(String(data: data, encoding: .utf8))
            let xml = NSString(data: data, encoding: NSUTF8StringEncoding)
            print(xml)
        }
    }


    func setRelativeVolume(ipAddress: String, volume: Int) async -> Int {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
            "Adjustment": volume
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "SetRelativeVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return 0 }
            let volume = XMLParserSonos().parseRelativeVolume(xml: xmlString)
            return volume
        }

        return 0
    }


    func getVolume(ipAddress: String) async -> Double {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Channel": "Master",
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetVolume", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return 0 }
            let volume = XMLParserSonos().parseVolume(xml: xmlString)
            return Double(volume)
        }

        return 0
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

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "Pause", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
        }
    }

    func play(ipAddress: String) async {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "Speed": 1
        ]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "Play", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {

        }
    }


    func playbackInfo(ipAddress: String) async -> String {
        let arguments: [String: Any] = [
            "InstanceID": 0,
        ]


        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetTransportInfo", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {

            guard let xmlString = String(data: data, encoding: .utf8) else { return "" }
            let playbackInfo = XMLParserSonos().parsePlaybackInfo(xml: xmlString)
            return playbackInfo
        }

        return ""
    }


    

    func getZoneInformation(ipAddress: String) {
        let arguments: [String: Any] = [:]

//        sendSoapRequest(action: "GetZoneGroupState", arguments: arguments, ipAddress: ipAddress) { data, error in
//            if let error = error {
//                print("Error getting zone information: \(error.localizedDescription)")
//                return
//            }
//            guard let data = data else { return }
//            let xml = SWXMLHash.parse(data)
//            let groups = xml["ZoneGroups"]["ZoneGroup"].all
//
//            for group in groups {
//                let coordinator = group["ZoneGroupCoordinator"].element?.attribute(by: "IPAddress")?.text ?? ""
//                let members = group["ZoneGroupMember"].all.map { $0.element?.attribute(by: "UUID")?.text ?? "" }
//                print("Coordinator: \(coordinator), Members: \(members)")
//            }
//        }
    }

    func getBatteryLevel(ipAddress: String) {
        guard let url = URL(string: "http://\(ipAddress):1400/status/batterystatus") else { return }
        var request = URLRequest(url: url)

        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            print(String(data: data!, encoding: .utf8))
        }
        task.resume()
    }

    func getZones(ipAddress: String) async -> [ZoneGroup] {
        let arguments: [String: Any] = [:]

        if let (data, _) = try? await sendSoapRequest(ip: ipAddress, action: "GetZoneGroupState", arguments: arguments, endpoint: "ZoneGroupTopology") {
            guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
            let zones = XMLParserSonos().parseZones(xml: xmlString.unescaped)
            return zones
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
                         return Room(UUID: $0.UUID, location: $0.location, zoneName: $0.zoneName)
                     } else {
                         return nil
                     }
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

    func queue(song: String, IP: String) async {
        var enqueuedURIMetadata = """
        &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="10032020song%3a\(song)" restricted="true"&gt;&lt;dc:title&gt;Apple Music&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON52231_X_#Svc52231-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """

        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EnqueuedURI": "x-sonos-http:song%3a\(song).mp4?sid=204&amp;flags=8224&amp;sn=5",
            "EnqueuedURIMetaData": enqueuedURIMetadata,
            "DesiredFirstTrackNumberEnqueued": 0,
            "EnqueueAsNext": 0
        ]

        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "AddURIToQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }

    func setAVTransport(song: String, IP: String) async {
//        var enqueuedURIMetadata = """
//&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="10032020song%3a\(song)" restricted="true"&gt;&lt;dc:title&gt;Apple Music&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON52231_X_#Svc52231-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
//        """
//
//        let arguments: [String: Any] = [
//            "InstanceID": 0,
//            "EnqueuedURI": "x-sonos-http:song%3a\(song).mp4?sid=204&amp;flags=8224&amp;sn=5",
//            "EnqueuedURIMetaData": enqueuedURIMetadata,
//            "DesiredFirstTrackNumberEnqueued": 0,
//            "EnqueueAsNext": 0
//        ]
//
//        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
//          <s:Body>
//            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
//              <InstanceID>0</InstanceID>
//              <CurrentURI>x-rincon-queue:RINCON_7828CAC7352E01400#0</CurrentURI>
//              <CurrentURIMetaData/>
//            </u:SetAVTransportURI>
//          </s:Body>
//        </s:Envelope>


//        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "RemoveAllTracksFromQueue", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
//            if (response as? HTTPURLResponse)?.statusCode != 200 {
//                print("Failed")
//            }
//        }
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

    func sendSoapRequest(ip: String, action: String, arguments: [String: Any], endpoint: String) async throws -> (Data, URLResponse)? {
        guard let request = createSoapRequest(ip: ip, action: action, arguments: arguments, endpoint: endpoint) else {
            return nil
        }
        return try await URLSession.shared.data(for: request)
    }


}
