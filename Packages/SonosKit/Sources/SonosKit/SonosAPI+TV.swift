import Foundation

extension SonosAPI {
    func getDialogLevel(IP: String) async throws -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "DialogLevel")
        ]
        
        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try xmlParser.parseForCurrentValue(xml: xml)
    }

    func setDialogLevel(IP: String, enabled: Bool) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "DialogLevel"),
            ("DesiredValue", enabled ? 1 : 0)
        ]
        
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
    }

    func getSpeechEnhanceEnabled(IP: String) async throws -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "SpeechEnhanceEnabled")
        ]
        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try xmlParser.parseForCurrentValue(xml: xml)
    }

    func setSpeechEnhanceEnabled(IP: String, enabled: Bool) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "SpeechEnhanceEnabled"),
            ("DesiredValue", enabled ? 1 : 0)
        ]
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SonosAPIError.failedLoading
        }
    }

    func getDialogLevelValue(IP: String) async throws -> Int {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "DialogLevel")
        ]
        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return 1 }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SonosAPIError.failedLoading
        }
        guard let value: Double = xmlParser.extractValue(from: data, for: "CurrentValue") else { return 1 }
        return Int(value)
    }

    func setDialogLevelValue(IP: String, value: Int) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "DialogLevel"),
            ("DesiredValue", value)
        ]
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SonosAPIError.failedLoading
        }
    }

    func getNightMode(IP: String) async throws -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", "NightMode")
        ]
        
        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try xmlParser.parseForCurrentValue(xml: xml)
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
            throw SonosAPIError.failedLoading
        }
    }

    func getEQValue(IP: String, eq: EQType) async -> Double? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", eq.rawValue)
        ]
        
        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return nil }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            return nil
        }
        guard let value: Double = xmlParser.extractValue(from: data, for: "CurrentValue") else { return nil }
        return value
    }

    func setEQValue(IP: String, eq: EQType, value: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", eq.rawValue),
            ("DesiredValue", value)
        ]
        
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
        }
    }

    func getAudioInputFormat(IP: String) async throws -> AudioInputFormat {
        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetZoneInfo", arguments: [], endpoint: "DeviceProperties") else { return .unknown }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try xmlParser.parseForHTAudioIn(xml: xml)
    }

    func tvInput(IP: String, ID: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("CurrentURI", "x-sonos-htastream:\(ID):spdif"),
            ("CurrentURIMetaData", "")
        ]
        
        if let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetAVTransportURI", arguments: arguments, endpoint: "MediaRenderer/AVTransport") {
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Failed")
            }
        }
    }
}
