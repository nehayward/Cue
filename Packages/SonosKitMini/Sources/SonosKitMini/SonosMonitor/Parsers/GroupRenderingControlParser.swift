import Foundation

final class GroupRenderingControlParser {
    typealias Event = SonosGroupRenderingEvent
    
    // Function to parse the full XML response
    static func parse(xmlString: String) -> Event? {
        let pattern = "<([^>]+)>([^<]+)</\\1>"
        var properties: [String: String] = [:]
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))
            
            for match in matches {
                guard let tagRange = Range(match.range(at: 1), in: xmlString),
                      let valueRange = Range(match.range(at: 2), in: xmlString) else {
                    continue
                }
                
                let tag = String(xmlString[tagRange])
                let value = String(xmlString[valueRange])
                properties[tag] = value
            }
        } catch {
            print("Error parsing XML: \(error)")
            return nil
        }
        
        // Convert properties to appropriate types
        let groupVolume = Int(properties["GroupVolume"] ?? "")
        let groupMute = properties["GroupMute"].flatMap { $0 == "1" }
        let groupVolumeChangeable = properties["GroupVolumeChangeable"].flatMap { $0 == "1" }
        
        return Event(
            groupVolume: groupVolume,
            groupMute: groupMute,
            groupVolumeChangeable: groupVolumeChangeable
        )
    }
    
    // Remove other unused methods if they're not needed for this parser
}
