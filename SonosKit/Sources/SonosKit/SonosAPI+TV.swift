import Foundation

extension SonosAPI {
    func getDialogLevel(IP: String) async throws -> Bool {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EQType": "DialogLevel",
        ]

        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try XMLParserSonos().parseForCurrentValue(xml: xml)
    }

    func setDialogLevel(IP: String, enabled: Bool) async throws {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EQType": "DialogLevel",
            "DesiredValue": enabled ? 1 : 0,
        ]

        guard let (_, response) = try await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
    }

    func getNightMode(IP: String) async throws -> Bool {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EQType": "NightMode",
        ]

        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try XMLParserSonos().parseForCurrentValue(xml: xml)
    }

    func setNightMode(IP: String, enabled: Bool) async throws {
        let arguments: [String: Any] = [
            "InstanceID": 0,
            "EQType": "NightMode",
            "DesiredValue": enabled ? 1 : 0,
        ]

        guard let (_, response) = try await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
    }

    func getAudioInputFormat(IP: String) async throws -> AudioInputFormat {
        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetZoneInfo", arguments: [:], endpoint: "DeviceProperties") else { return .unknown }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Failed with \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try XMLParserSonos().parseForHTAudioIn(xml: xml)
    }
}
