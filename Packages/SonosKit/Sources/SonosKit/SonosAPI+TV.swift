import DanceLogger
import Foundation

extension SonosAPI {
    /// Reads an EQ type, keeping "the device said no" (a UPnP fault — `.unsupported`)
    /// apart from "we never got an answer" (`.failedLoading`). Never substitutes a
    /// value for a request that didn't land: these reads double as capability probes,
    /// so a fabricated fallback silently mis-detects the speaker.
    private func getEQ(IP: String, _ eq: EQType) async throws -> Data {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", eq.rawValue)
        ]

        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            throw SonosAPIError.failedLoading
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            DanceLog.sonos.error("GetEQ \(eq.rawValue) failed: HTTP \(httpResponse.statusCode)")
            throw SonosAPIError.unsupported
        }
        return data
    }

    /// Writes an EQ type, with the same distinction as `getEQ`.
    private func setEQ(IP: String, _ eq: EQType, value: Int) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", eq.rawValue),
            ("DesiredValue", value)
        ]

        guard let (_, response) = try await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else {
            throw SonosAPIError.failedLoading
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            DanceLog.sonos.error("SetEQ \(eq.rawValue) failed: HTTP \(httpResponse.statusCode)")
            throw SonosAPIError.unsupported
        }
    }

    /// Reads an EQ type as its on/off flag.
    private func getEQFlag(IP: String, _ eq: EQType) async throws -> Bool {
        let data = try await getEQ(IP: IP, eq)
        return try xmlParser.parseForCurrentValue(xml: String(decoding: data, as: UTF8.self))
    }

    func getDialogLevel(IP: String) async throws -> Bool {
        try await getEQFlag(IP: IP, .dialogLevel)
    }

    func setDialogLevel(IP: String, enabled: Bool) async throws {
        try await setEQ(IP: IP, .dialogLevel, value: enabled ? 1 : 0)
    }

    func getSpeechEnhanceEnabled(IP: String) async throws -> Bool {
        try await getEQFlag(IP: IP, .speechEnhanceEnabled)
    }

    func setSpeechEnhanceEnabled(IP: String, enabled: Bool) async throws {
        try await setEQ(IP: IP, .speechEnhanceEnabled, value: enabled ? 1 : 0)
    }

    func getDialogLevelValue(IP: String) async throws -> Int {
        let data = try await getEQ(IP: IP, .dialogLevel)
        guard let value: Double = xmlParser.extractValue(from: data, for: "CurrentValue") else {
            throw SonosAPIError.failedParsing
        }
        return Int(value)
    }

    func setDialogLevelValue(IP: String, value: Int) async throws {
        try await setEQ(IP: IP, .dialogLevel, value: value)
    }

    // Night mode keeps its own request handling rather than moving onto `getEQ`/`setEQ`.
    // Those throw where these return a value or succeed silently, and night mode is the
    // one control in here with no reported problem — changing how it reports failure
    // belongs with the fix to `SetNightModeIntent`'s error messages, not with this.
    func getNightMode(IP: String) async throws -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", EQType.nightMode.rawValue)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "GetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return false }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed: HTTP \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
        let xml = String(decoding: data, as: UTF8.self)
        return try xmlParser.parseForCurrentValue(xml: xml)
    }

    func setNightMode(IP: String, enabled: Bool) async throws {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("EQType", EQType.nightMode.rawValue),
            ("DesiredValue", enabled ? 1 : 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "SetEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed: HTTP \(httpResponse.statusCode)")
            throw SonosAPIError.failedLoading
        }
    }

    func getEQValue(IP: String, eq: EQType) async -> Double? {
        guard let data = try? await getEQ(IP: IP, eq) else { return nil }
        return xmlParser.extractValue(from: data, for: "CurrentValue")
    }

    func setEQValue(IP: String, eq: EQType, value: Int) async {
        try? await setEQ(IP: IP, eq, value: value)
    }

    func getAudioInputFormat(IP: String) async throws -> AudioInputFormat {
        guard let (data, response) = try await sendSoapRequest(ip: IP, action: "GetZoneInfo", arguments: [], endpoint: "DeviceProperties") else { return .unknown }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed: HTTP \(httpResponse.statusCode)")
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
                DanceLog.sonos.error("\(#function) failed")
            }
        }
    }
}
