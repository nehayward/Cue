import Foundation

final class AlarmListParser {
    // First extract the Alarms content
    private static let alarmsPattern = #"<Alarms>(.*?)</Alarms>"#
    // Then match each Alarm tag
    private static let alarmPattern = #"<Alarm[^>]+/>"#
    // Capture full metadata content between ProgramMetaData=" and next attribute
    private static let metadataPattern = #"ProgramMetaData="([^"]*(?:"[^"]*)*)"(?=\s+(?:PlayMode|Volume|IncludeLinkedZones)=")"#
    // Match other attributes, excluding metadata
    private static let attributePattern = #"(?<!ProgramMeta)\b(\w+)="([^"]*)""#
    
    private var alarms: [Alarm] = []
    
    func parseAlarms(from xml: String) -> [Alarm] {
        var alarms: [Alarm] = []
        let unescapedXML = xml.unescaped
        
        print("Input XML: \(unescapedXML)") // Debug logging
        
        // First extract the Alarms section
        guard let alarmsRegex = try? NSRegularExpression(pattern: Self.alarmsPattern, options: [.dotMatchesLineSeparators]),
              let match = alarmsRegex.firstMatch(in: unescapedXML, options: [], range: NSRange(unescapedXML.startIndex..<unescapedXML.endIndex, in: unescapedXML)),
              let alarmsRange = Range(match.range(at: 1), in: unescapedXML) else {
            print("Could not find Alarms section") // Debug logging
            return []
        }
        
        let alarmsContent = String(unescapedXML[alarmsRange])
        print("Found alarms section: \(alarmsContent)") // Debug logging
        
        // Then find all individual Alarm tags
        guard let alarmRegex = try? NSRegularExpression(pattern: Self.alarmPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        
        let alarmMatches = alarmRegex.matches(in: alarmsContent, options: [], range: NSRange(alarmsContent.startIndex..<alarmsContent.endIndex, in: alarmsContent))
        
        print("Found \(alarmMatches.count) alarm tags") // Debug logging
        
        // Parse each alarm
        for alarmMatch in alarmMatches {
            guard let alarmRange = Range(alarmMatch.range, in: alarmsContent) else { continue }
            let alarmString = String(alarmsContent[alarmRange])
            print("\nParsing alarm: \(alarmString)") // Debug logging
            
            // First extract metadata content
            var programMetaData = ""
            if let metadataRegex = try? NSRegularExpression(pattern: Self.metadataPattern, options: [.dotMatchesLineSeparators]),
               let metadataMatch = metadataRegex.firstMatch(in: alarmString, options: [], range: NSRange(alarmString.startIndex..<alarmString.endIndex, in: alarmString)),
               let metadataRange = Range(metadataMatch.range(at: 1), in: alarmString) {
                programMetaData = String(alarmString[metadataRange])
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&amp;", with: "&")
                print("Found metadata: \(programMetaData)") // Debug
            }
            
            // Parse other attributes
            var attributes: [String: String] = [:]
            if let attrRegex = try? NSRegularExpression(pattern: Self.attributePattern, options: []) {
                let attrMatches = attrRegex.matches(in: alarmString, options: [], range: NSRange(alarmString.startIndex..<alarmString.endIndex, in: alarmString))
                
                for attrMatch in attrMatches {
                    guard let keyRange = Range(attrMatch.range(at: 1), in: alarmString),
                          let valueRange = Range(attrMatch.range(at: 2), in: alarmString) else { continue }
                    
                    let key = String(alarmString[keyRange])
                    let value = String(alarmString[valueRange])
                    attributes[key] = value
                    
                    print("Parsing attribute: \(key) = \(value)") // Debug logging
                }
            }
            
            // Check if it's a buzzer alarm and set empty metadata if it is
            if let programURI = attributes["ProgramURI"], programURI == "x-rincon-buzzer:0" {
                programMetaData = ""
            }
            
            // Add metadata back to attributes
            attributes["ProgramMetaData"] = programMetaData
            
            print("Final attributes: \(attributes)") // Debug logging
            
            // Create alarm from attributes
            if let alarm = createAlarm(from: attributes) {
                alarms.append(alarm)
                print("Created alarm with ID: \(alarm.id)") // Debug logging
            } else {
                print("Failed to create alarm from attributes") // Debug logging
            }
        }
        
        return alarms
    }
    
    private func createAlarm(from attributes: [String: String]) -> Alarm? {
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
        let programMetaData = attributes["ProgramMetaData"] ?? ""
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
