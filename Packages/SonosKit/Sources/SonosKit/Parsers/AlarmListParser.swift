import Foundation

final class AlarmListParser {
    // Extract the <Alarms>…</Alarms> section.
    private static let alarmsPattern = #"<Alarms>(.*?)</Alarms>"#
    // Marks the start of each alarm element. Segmenting on the start tag —
    // rather than anchoring on a trailing attribute, as the old
    // `<Alarm[^>]+/>` did — keeps parsing independent of attribute order and
    // tolerant of `>` inside decoded (single-escaped) metadata.
    private static let alarmStartPattern = #"<Alarm\b"#
    // ProgramMetaData is the only attribute whose value may contain quotes or
    // angle brackets, so its end is bounded by the next real Sonos attribute
    // or the tag's end — not by the first `"`. The attribute list makes this
    // order-independent; an interior DIDL `…/>` is ignored because the `/>`
    // alternative is anchored to the end of the (per-alarm) string.
    private static let metadataPattern = #"ProgramMetaData="(.*?)"(?=\s*(?:/>\s*$|(?:ID|StartTime|Duration|Recurrence|Enabled|RoomUUID|ProgramURI|PlayMode|Volume|IncludeLinkedZones)="))"#
    // Once ProgramMetaData is removed, every remaining attribute has a simple
    // value, so a single order-independent sweep is safe.
    private static let attributePattern = #"\b(\w+)="([^"]*)""#

    func parseAlarms(from xml: String) -> [Alarm] {
        // Preferred path: decode a single entity level so the inner <Alarms>
        // document stays well-formed, then let Foundation's XMLParser do the
        // parsing. This is robust to attribute values that contain quotes or
        // angle brackets (i.e. every music alarm's DIDL metadata).
        if let parsed = parseWithXMLParser(from: xml), !parsed.isEmpty {
            return parsed
        }
        // Fallback for responses the XMLParser can't make sense of (e.g.
        // single-escaped metadata, which leaves literal `<`/`>` inside an
        // attribute and is therefore not well-formed XML).
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
        let unescapedXML = xml.unescaped

        // Isolate the <Alarms>…</Alarms> section.
        guard let alarmsContent = Self.value(Self.alarmsPattern, in: unescapedXML, dotMatchesNewlines: true) else {
            return []
        }

        // Segment into individual alarms by their start tags. This is robust to
        // attribute order and to `>` characters inside decoded metadata, both of
        // which broke the previous tag-matching approaches.
        guard let startRegex = try? NSRegularExpression(pattern: Self.alarmStartPattern) else { return [] }
        let content = alarmsContent as NSString
        let starts = startRegex.matches(in: alarmsContent, range: NSRange(location: 0, length: content.length)).map(\.range.location)
        guard !starts.isEmpty else { return [] }

        // Compile the per-alarm patterns once rather than per attribute.
        let metadataRegex = try? NSRegularExpression(pattern: Self.metadataPattern, options: [.dotMatchesLineSeparators])
        let attributeRegex = try? NSRegularExpression(pattern: Self.attributePattern)

        var alarms: [Alarm] = []
        for (index, start) in starts.enumerated() {
            let end = (index + 1 < starts.count) ? starts[index + 1] : content.length
            let alarmString = content.substring(with: NSRange(location: start, length: end - start))

            var attributes: [String: String] = [:]

            // Pull ProgramMetaData out first and strip it, so the sweep below
            // only ever sees simple (quote-free) attribute values.
            var cleaned = alarmString
            if let metadataRegex,
               let match = metadataRegex.firstMatch(in: alarmString, range: NSRange(alarmString.startIndex..<alarmString.endIndex, in: alarmString)),
               let valueRange = Range(match.range(at: 1), in: alarmString),
               let wholeRange = Range(match.range(at: 0), in: alarmString) {
                attributes["ProgramMetaData"] = String(alarmString[valueRange])
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&amp;", with: "&")
                cleaned = String(alarmString[..<wholeRange.lowerBound]) + String(alarmString[wholeRange.upperBound...])
            }

            // Sweep the remaining attributes in any order.
            if let attributeRegex {
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                for match in attributeRegex.matches(in: cleaned, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: cleaned),
                          let valueRange = Range(match.range(at: 2), in: cleaned) else { continue }
                    attributes[String(cleaned[keyRange])] = String(cleaned[valueRange])
                }
            }

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
