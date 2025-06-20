import Foundation

extension SonosAPI {
    func subscribeToSonos(port: Int, deviceIP: String, sonosIP: String) async throws {
        guard !deviceIP.isEmpty else {
            print("❌ Cannot subscribe: Device IP not available")
            throw NSError(domain: "MediaServerHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Device IP not available"])
        }
        
        let url = URL(string: "http://\(sonosIP):1400/ZoneGroupTopology/Event")!
        var request = URLRequest(url: url)
        request.httpMethod = "SUBSCRIBE"
        request.setValue("<http://\(deviceIP):\(port)>", forHTTPHeaderField: "CALLBACK")
        request.setValue("upnp:event", forHTTPHeaderField: "NT")
        request.setValue("Second-500", forHTTPHeaderField: "TIMEOUT")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "MediaServerHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "MediaServerHandler", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Subscription failed with status code: \(httpResponse.statusCode)"])
            }
            
            // Store the SID for future renewals
            if let sid = httpResponse.allHeaderFields["SID"] as? String {
                print("✅ Successfully subscribed to Sonos device. SID: \(sid)")
                // TODO: Store SID for renewal
            }
            
            print("📡 Sonos subscription response: \(httpResponse.statusCode)")
            print("Response headers: \(httpResponse.allHeaderFields)")
        } catch {
            print("❌ Failed to subscribe to Sonos device: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getDeviceID(IP: String) async -> String? {
        let arguments: OrderedKeys = [
            ("VariableName", "R_TrialZPSerial")
        ]

        guard let (data, _) = try? await sendSoapRequest(ip: IP, action: "GetString", arguments: arguments, endpoint: "SystemProperties") else {
            return nil
        }

        let xml = String(decoding: data, as: UTF8.self)
        if let deviceID = try? xmlParser.parseValue(xml: xml, named: "StringValue") {
            return deviceID
        }
        return nil
    }

}
