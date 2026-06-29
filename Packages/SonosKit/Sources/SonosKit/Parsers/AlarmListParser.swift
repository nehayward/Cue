import Foundation

final class AlarmListParser {
    // Extract the <Alarms>…</Alarms> section.
    private static let alarmsPattern = #"<Alarms>(.*?)</Alarms>"#
    // Match each Alarm element by anchoring on its final attribute rather than
    // on the next `>`. The old `<Alarm[^>]+/>` broke whenever an alarm's
    // ProgramMetaData decoded to contain a literal `>` (single-escaped DIDL),
    // silently dropping that alarm.
    private static let alarmPattern = #"<Alarm\b.*?\bIncludeLinkedZones="[^"]*"\s*/>"#

    func parseAlarms(from xml: String) -> [Alarm] {
        // Preferred path: decode a single entity level so the inner <Alarms>
        // document stays well-formed, then let Foundation's XMLParser do the
        // parsing. This is robust to attribute values that contain quotes or
        // angle brackets (i.e. every music alarm's DIDL metadata) — the cases
        // that silently broke the `<Alarm[^>]+/>` regex below.
        if let parsed = parseWithXMLParser(from: xml), !parsed.isEmpty {
            return parsed
        }
        // Fallback for any response the XMLParser can't make sense of so we
        // never regress to fewer alarms than the legacy regex would surface.
        return parseWithRegex(from: xml)
    }

    private func parseWithXMLParser(from xml: String) -> [Alarm]? {
        let decoded = xml.xmlEntityDecodedOnce
        guard let start = decoded.range(of: "<Alarms>"),
              let end = decoded.range(of: "</Alarms>"),
              start.upperBound <= end.lowerBound else {
            return nil
        }

        let alarmsDoc = String(decoded[start.lowerBound..<end.upperBound])
        guard let data = alarmsDoc.data(using: .utf8) else { return nil }

        let delegate = AlarmsXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.alarms
    }

    private func parseWithRegex(from xml: String) -> [Alarm] {
        var alarms: [Alarm] = []
        let unescapedXML = xml.unescaped

        // First extract the Alarms section
        guard let alarmsRegex = try? NSRegularExpression(pattern: Self.alarmsPattern, options: [.dotMatchesLineSeparators]),
              let match = alarmsRegex.firstMatch(in: unescapedXML, options: [], range: NSRange(unescapedXML.startIndex..<unescapedXML.endIndex, in: unescapedXML)),
              let alarmsRange = Range(match.range(at: 1), in: unescapedXML) else {
            return []
        }

        let alarmsContent = String(unescapedXML[alarmsRange])

        // Then find all individual Alarm tags
        guard let alarmRegex = try? NSRegularExpression(pattern: Self.alarmPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let alarmMatches = alarmRegex.matches(in: alarmsContent, options: [], range: NSRange(alarmsContent.startIndex..<alarmsContent.endIndex, in: alarmsContent))

        // Parse each alarm. Each field is extracted with a targeted pattern so
        // that embedded quotes or angle brackets inside ProgramMetaData can't
        // desync the parse (which a single sweep of `\w+="…"` was prone to).
        for alarmMatch in alarmMatches {
            guard let alarmRange = Range(alarmMatch.range, in: alarmsContent) else { continue }
            let alarmString = String(alarmsContent[alarmRange])

            var attributes: [String: String] = [:]
            // Attributes that sit before ProgramMetaData are always clean.
            for key in ["ID", "StartTime", "Duration", "Recurrence", "Enabled", "RoomUUID", "ProgramURI"] {
                if let value = Self.value(#"\b\#(key)="([^"]*)""#, in: alarmString) {
                    attributes[key] = value
                }
            }
            // Trailing attributes are anchored on their neighbours so the
            // (possibly messy) metadata in between is skipped over.
            attributes["PlayMode"] = Self.value(#"\bPlayMode="([^"]*)"\s+Volume="#, in: alarmString)
            attributes["Volume"] = Self.value(#"\bVolume="([^"]*)"\s+IncludeLinkedZones="#, in: alarmString)
            attributes["IncludeLinkedZones"] = Self.value(#"\bIncludeLinkedZones="([^"]*)"\s*/>"#, in: alarmString)

            // Metadata is whatever sits between ProgramMetaData=" and PlayMode=.
            var programMetaData = Self.value(#"\bProgramMetaData="(.*?)"\s+PlayMode="#, in: alarmString, dotMatchesNewlines: true) ?? ""
            programMetaData = programMetaData
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
            attributes["ProgramMetaData"] = programMetaData

            if let alarm = Self.makeAlarm(from: attributes) {
                alarms.append(alarm)
            }
        }

        return alarms
    }

    /// First capture group of `pattern` in `text`, or nil.
    private static func value(_ pattern: String, in text: String, dotMatchesNewlines: Bool = false) -> String? {
        let options: NSRegularExpression.Options = dotMatchesNewlines ? [.dotMatchesLineSeparators] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    static func makeAlarm(from attributes: [String: String]) -> Alarm? {
        guard let id = attributes["ID"],
              let roomUUID = attributes["RoomUUID"],
              let startTime = attributes["StartTime"],
              let recurrence = attributes["Recurrence"],
              let enabled = attributes["Enabled"],
              let programURI = attributes["ProgramURI"],
              let volume = attributes["Volume"] else {
            return nil
        }

        let duration = attributes["Duration"] ?? ""
        // Buzzer alarms have no media metadata.
        let programMetaData = programURI == "x-rincon-buzzer:0" ? "" : (attributes["ProgramMetaData"] ?? "")
        let includeLinkedZones = attributes["IncludeLinkedZones"] ?? "0"
        let playMode = attributes["PlayMode"] ?? "NORMAL"

        return Alarm(
            id: id,
            roomID: roomUUID,
            enabled: enabled == "1",
            startTime: TimeParser.shared.parseTime(startTime),
            duration: TimeParser.shared.parseDuration(duration),
            schedule: Frequency(mode: recurrence),
            programURI: programURI,
            programMetaData: programMetaData,
            volume: Double(volume) ?? 0,
            includeLinkedZones: includeLinkedZones == "1",
            playMode: PlayMode(mode: playMode) ?? .normal,
            scheduleRaw: recurrence,
            shuffle: playMode == "SHUFFLE"
        )
    }
}

/// Collects every `<Alarm .../>` element. Using a real XML parser means
/// attribute values containing escaped DIDL metadata (quotes, `<`, `>`) are
/// handled correctly instead of derailing a hand-rolled attribute regex.
private final class AlarmsXMLDelegate: NSObject, XMLParserDelegate {
    var alarms: [Alarm] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Alarm" else { return }
        if let alarm = AlarmListParser.makeAlarm(from: attributeDict) {
            alarms.append(alarm)
        }
    }
}
