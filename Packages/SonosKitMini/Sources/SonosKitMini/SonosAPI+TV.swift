//
//  SonosMiniService+TV.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/30/24.
//


import Foundation

/// Why an EQ read/write didn't land. Keeping these apart matters for the speech
/// enhancement probe: a dropped request must not read as "this speaker doesn't
/// have the feature".
enum SonosEQError: Error {
    /// No answer from the speaker.
    case failedLoading
    /// The speaker answered with a fault — it doesn't implement this EQ type.
    case unsupported
    case failedParsing
}

extension SonosAPI {
    /// Reads an EQ type. Throws rather than substituting a value: these reads double
    /// as capability probes, and a fabricated fallback silently mis-detects the speaker.
    private func getEQ(IP: String, type: String) async throws -> String {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", type)
        ]

        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            throw SonosEQError.failedLoading
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("GetEQ \(type) failed with \(httpResponse.statusCode)")
            throw SonosEQError.unsupported
        }
        let xml = String(decoding: data, as: UTF8.self)
        guard let value = GenericXMLParser(targetElement: "CurrentValue").parseXML(xml) else {
            throw SonosEQError.failedParsing
        }
        return value
    }

    /// Writes an EQ type, with the same distinction as `getEQ`.
    private func setEQ(IP: String, type: String, value: Int) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", type),
            ("DesiredValue", value)
        ]

        guard let (_, response) = try await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            throw SonosEQError.failedLoading
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("SetEQ \(type) failed with \(httpResponse.statusCode)")
            throw SonosEQError.unsupported
        }
    }

    func getDialogLevel(IP: String) async throws -> Bool {
        try await getEQ(IP: IP, type: "DialogLevel") == "1"
    }

    func setDialogLevel(IP: String, enabled: Bool) async throws {
        try await setEQ(IP: IP, type: "DialogLevel", value: enabled ? 1 : 0)
    }

    func getSpeechEnhanceEnabled(IP: String) async throws -> Bool {
        try await getEQ(IP: IP, type: "SpeechEnhanceEnabled") == "1"
    }

    func setSpeechEnhanceEnabled(IP: String, enabled: Bool) async throws {
        try await setEQ(IP: IP, type: "SpeechEnhanceEnabled", value: enabled ? 1 : 0)
    }

    func getDialogLevelValue(IP: String) async throws -> Int {
        guard let value = Int(try await getEQ(IP: IP, type: "DialogLevel")) else {
            throw SonosEQError.failedParsing
        }
        return value
    }

    func setDialogLevelValue(IP: String, value: Int) async throws {
        try await setEQ(IP: IP, type: "DialogLevel", value: value)
    }

    func getNightMode(IP: String) async throws -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "NightMode")
        ]
        
        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
        }
        let xml = String(decoding: data, as: UTF8.self)
        let parser = GenericXMLParser(targetElement: "CurrentValue")
        if let value = parser.parseXML(xml) {
            return value == "1"
        }
        return false
    }

    func setNightMode(IP: String, enabled: Bool) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "NightMode"),
            ("DesiredValue", enabled ? 1 : 0)
        ]
        
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
//            throw SonosAPIError.failedLoading
        }
    }
//
//    func getEQValue(IP: String, eq: EQType) async -> Double? {
//        let arguments: OrderedKeys = [
//            ("InstanceID", 0),
//            ("EQType", eq.rawValue)
//        ]
//        
//        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return nil }
//        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
//            print("Failed with \(httpResponse.statusCode)")
//            return nil
//        }
//        guard let value: Double = xmlParser.extractValue(from: data, for: "CurrentValue") else { return nil }
//        return value
//    }
//
//    func setEQValue(IP: String, eq: EQType, value: Int) async {
//        let arguments: OrderedKeys = [
//            ("InstanceID", 0),
//            ("EQType", eq.rawValue),
//            ("DesiredValue", value)
//        ]
//        
//        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
//        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
//            print("Failed with \(httpResponse.statusCode)")
//        }
//    }

    func getAudioInputFormat(IP: String) async throws -> AudioInputFormat {
        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetZoneInfo", arguments: [], endpoint: "DeviceProperties") else { return .unknown }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
        }
        let xml = String(decoding: data, as: UTF8.self)
        let parser = GenericXMLParser(targetElement: "HTAudioIn")
        if let value = parser.parseXML(xml) {
            guard let value = Int(value), let audioInputFormat = AudioInputFormat(rawValue: value) else {
                return .unknown
            }
            return audioInputFormat
        }
        
        return .unknown
    }

//    func tvInput(IP: String, ID: String) async {
//        let arguments: OrderedKeys = [
//            ("InstanceID", 0),
//            ("CurrentURI", "x-sonos-htastream:\(ID):spdif"),
//            ("CurrentURIMetaData", "")
//        ]
//        
//        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
//            if (response as? HTTPURLResponse)?.statusCode != 200 {
//                print("Failed")
//            }
//        }
//    }
}
