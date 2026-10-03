
import DanceLogger
import Foundation

extension SonosAPI {
    func getBass(ipAddress: String) async -> Int? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: ipAddress, action: "GetBass", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return nil }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
            return nil
        }

        return xmlParser.extractValue(from: data, for: "CurrentBass")
    }

    func setBass(ipAddress: String, bass: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("DesiredBass", bass)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "SetBass", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
        }
    }

    func getTreble(ipAddress: String) async -> Int? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: ipAddress, action: "GetTreble", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return nil }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
            return nil
        }

        return xmlParser.extractValue(from: data, for: "CurrentTreble")
    }

    func setTreble(ipAddress: String, treble: Int) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("DesiredTreble", treble)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "SetTreble", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
        }
    }

    func getLoudness(ipAddress: String) async -> Bool? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master")
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: ipAddress, action: "GetLoudness", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return nil }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
            return nil
        }

        guard let value: Int = xmlParser.extractValue(from: data, for: "CurrentLoudness") else { return nil }
        return Bool(truncating: NSNumber(value: value))
    }

    func setLoudness(ipAddress: String, enabled: Bool) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0),
            ("Channel", "Master"),
            ("DesiredLoudness", enabled ? 1 : 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "SetLoudness", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
        }
    }

    func getTrueplayEnabled(ipAddress: String) async -> Bool? {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: ipAddress, action: "GetRoomCalibrationStatus", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return nil }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
            return nil
        }

        guard let value: Int = xmlParser.extractValue(from: data, for: "RoomCalibrationEnabled") else { return nil }
        return Bool(truncating: NSNumber(value: value))
    }

    func resetEQ(ipAddress: String) async {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: ipAddress, action: "ResetBasicEQ", arguments: arguments, endpoint: "MediaRenderer/RenderingControl") else { return }
        if (response as? HTTPURLResponse)?.statusCode != 200 {
            DanceLog.sonos.error("\(#function) failed")
        }
    }
}
