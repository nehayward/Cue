//
//  SonosAPI.swift
//  Listener
//
//  Created by Nick Hayward on 1/8/25.
//

// SonosAPI.swift
import Foundation

final class SonosSoapAPI {
    // Structure to hold position info response
    struct PositionInfo: Codable {
        let track: Int
        let trackDuration: String
        let relativeTime: String
    }
    
    // Structure to hold transport info response
    struct TransportInfo: Codable {
        let state: String
        let status: String
        let speed: String
    }
    
    // Constants for SOAP request
    private enum SOAPConstants {
        static let positionInfoEnvelope = """
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
        </u:GetPositionInfo>
    </s:Body>
</s:Envelope>
"""
        static let transportInfoEnvelope = """
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
        </u:GetTransportInfo>
    </s:Body>
</s:Envelope>
"""
        static let soapAction = "urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo"
        static let transportInfoAction = "urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo"
    }
    
    // Get position info for a device
    static func getPositionInfo(deviceIP: String) async throws -> PositionInfo {
        guard let url = URL(string: "http://\(deviceIP):1400/MediaRenderer/AVTransport/Control") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(SOAPConstants.soapAction, forHTTPHeaderField: "SOAPAction")
        request.httpBody = SOAPConstants.positionInfoEnvelope.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Parse XML response and return position info
        let parser = PositionInfoParser()
        let positionInfo = try parser.parse(data: data)
        return positionInfo
    }
    
    // Get transport info for a device
    static func getTransportInfo(deviceIP: String) async throws -> TransportInfo {
        guard let url = URL(string: "http://\(deviceIP):1400/MediaRenderer/AVTransport/Control") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(SOAPConstants.transportInfoAction, forHTTPHeaderField: "SOAPAction")
        request.httpBody = SOAPConstants.transportInfoEnvelope.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Parse XML response and return transport info
        let parser = TransportInfoParser()
        let transportInfo = try parser.parse(data: data)
        return transportInfo
    }
    
    // Add transport state polling method
    static func pollTransportInfo(deviceIP: String) async throws -> Bool{
        let maxAttempts = 10  // Maximum number of polling attempts
        let pollingInterval: TimeInterval = 0.5  // Poll every 0.5 seconds
        
        for _ in 0..<maxAttempts {
            let transportInfo = try await getTransportInfo(deviceIP: deviceIP)
            
            // Check if we've reached a stable state
            let state = transportInfo.state.uppercased()
            if state == "PLAYING" || state == "PAUSED_PLAYBACK" {
                print("---------- State ----------")
                return state == "PLAYING"
            }
            
            // Wait before next poll
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }
        
        // If we reach here, we've exceeded maximum attempts
        throw NSError(domain: "SonosAPIError", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Transport state polling timeout"])
    }
}

// Position Info XML Parser
class PositionInfoParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var track = 0
    private var trackDuration = ""
    private var relativeTime = ""
    
    func parse(data: Data) throws -> SonosSoapAPI.PositionInfo {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            throw NSError(domain: "SonosAPIError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse XML"])
        }
        
        return SonosSoapAPI.PositionInfo(track: track, trackDuration: trackDuration, relativeTime: relativeTime)
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        
        switch currentElement {
        case "Track":
            track = Int(value) ?? 0
        case "TrackDuration":
            trackDuration = value
        case "RelTime":
            relativeTime = value
        default:
            break
        }
    }
}

// Transport Info XML Parser
class TransportInfoParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var state = ""
    private var status = ""
    private var speed = ""
    
    func parse(data: Data) throws -> SonosSoapAPI.TransportInfo {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            throw NSError(domain: "SonosAPIError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse XML"])
        }
        
        return SonosSoapAPI.TransportInfo(state: state, status: status, speed: speed)
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        
        switch currentElement {
        case "CurrentTransportState":
            state = value
        case "CurrentTransportStatus":
            status = value
        case "CurrentSpeed":
            speed = value
        default:
            break
        }
    }
}
