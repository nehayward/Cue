import Foundation

extension SonosAPI {
    func editAlarm(IP: String, alarm: Alarm, content: PlayableContent?) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        var arguments: OrderedKeys = [
            ("ID", alarm.id),
            ("Enabled", alarm.enabled ? "1" : "0"),
            ("StartLocalTime", dateFormatter.string(from: alarm.startTime)),
            ("Duration", alarm.duration == .zero ? "" : alarm.durationAlarm),
            ("Recurrence", alarm.schedule.alarmSchedule),
            ("RoomUUID", alarm.roomID),
            ("ProgramURI", alarm.programURI.encodeProgramURI),
            ("ProgramMetaData", alarm.programMetaData?.encodeProgramURI.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            ("PlayMode", alarm.shuffle ? "SHUFFLE" : "REPEAT_ALL"),
            ("Volume", alarm.volume),
            ("IncludeLinkedZones", alarm.includeLinkedZones ? "1" : "0")
        ]

        if let content {
            arguments[6].value = content.uri
            arguments[7].value = content.URIMetadata
        }

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "UpdateAlarm", arguments: arguments, endpoint: "AlarmClock") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func createAlarm(IP: String, alarm: Alarm, content: PlayableContent?) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        let arguments: OrderedKeys = [
            ("Enabled", alarm.enabled ? "1" : "0"),
            ("StartLocalTime", dateFormatter.string(from: alarm.startTime)),
            ("Duration", alarm.duration == .zero ? "" : alarm.durationAlarm),
            ("Recurrence", alarm.schedule.alarmSchedule),
            ("RoomUUID", alarm.roomID),
            ("ProgramURI", content?.uri ?? "x-rincon-buzzer:0"),
            ("ProgramMetaData", content?.URIMetadata ?? ""),
            ("PlayMode", alarm.shuffle ? "SHUFFLE" : "REPEAT_ALL"),
            ("Volume", alarm.volume),
            ("IncludeLinkedZones", alarm.includeLinkedZones ? "1" : "0")
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "CreateAlarm", arguments: arguments, endpoint: "AlarmClock") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func deleteAlarm(IP: String, alarm: Alarm) async {
        let arguments: OrderedKeys = [
            ("ID", alarm.id)
        ]
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "DestroyAlarm", arguments: arguments, endpoint: "AlarmClock") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func enableAlarm(IP: String, alarm: Alarm) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        let arguments: OrderedKeys = [
            ("ID", alarm.id),
            ("Enabled", alarm.enabled ? "1" : "0"),
            ("StartLocalTime", dateFormatter.string(from: alarm.startTime)),
            ("Duration", ""),
            ("Recurrence", alarm.scheduleRaw),
            ("RoomUUID", alarm.roomID),
            ("ProgramURI", alarm.programURI.encodeProgramURI),
            ("ProgramMetaData", alarm.programMetaData?.encodeProgramURI.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            ("PlayMode", "REPEAT_ALL"),
            ("Volume", alarm.volume),
            ("IncludeLinkedZones", alarm.includeLinkedZones ? "1" : "0")
        ]

        print(alarm.programMetaData?.encodeProgramURI.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "UpdateAlarm", arguments: arguments, endpoint: "AlarmClock") else {
            return
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
        }
    }

    func listAlarms(IP: String) async -> [Alarm] {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (data, response) = try? await sendSoapRequest(ip: IP, action: "ListAlarms", arguments: arguments, endpoint: "AlarmClock") else {
            return []
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            print("Failed")
            return []
        }

        let xml = String(decoding: data, as: UTF8.self)
        return xmlParser.parseAlarmClockList(from: xml)
    }

    func getRunningAlarm(IP: String) async -> Bool {
        let arguments: OrderedKeys = [
            ("InstanceID", 0)
        ]

        guard let (_, response) = try? await sendSoapRequest(ip: IP, action: "GetRunningAlarmProperties", arguments: arguments, endpoint: "MediaRenderer/AVTransport") else {
            return false
        }

        if (response as? HTTPURLResponse)?.statusCode != 200 {
            return false
        }

        return true
    }
}
