import Foundation

// Your imports remain the same
final class RenderingControlParser {
    // Function to parse the full XML response
    static func parse(xmlString: String) -> SonosRenderingControlEvent? {
        print(xmlString.unescaped)
        
        // First extract LastChange content using index access instead of safe
        let components = xmlString.components(separatedBy: "<LastChange>")
        guard components.count > 1,
              let lastChangeContent = components[1].components(separatedBy: "</LastChange>").first,
              let unescapedLastChange = lastChangeContent.removingHTMLEntities() else {
            print("FAILED --------")
            return nil
        }

        // Extract volume and mute controls
        let masterVolume = extractIntValue(from: unescapedLastChange, forTag: "Volume channel=\"Master\"") ?? 0
        let masterMute = extractBoolValue(from: unescapedLastChange, forTag: "Mute channel=\"Master\"") ?? false
        
        // Extract audio settings
        let bass = extractIntValue(from: unescapedLastChange, forTag: "Bass") ?? 0
        let treble = extractIntValue(from: unescapedLastChange, forTag: "Treble") ?? 0
        let loudness = extractBoolValue(from: unescapedLastChange, forTag: "Loudness channel=\"Master\"") ?? false
        let outputFixed = extractBoolValue(from: unescapedLastChange, forTag: "OutputFixed") ?? false
        
        // Extract speaker configuration
        let speakerSize = extractIntValue(from: unescapedLastChange, forTag: "SpeakerSize")
        let subGain = extractIntValue(from: unescapedLastChange, forTag: "SubGain")
        let subCrossover = extractIntValue(from: unescapedLastChange, forTag: "SubCrossover")
        let subPolarity = extractIntValue(from: unescapedLastChange, forTag: "SubPolarity")
        let subEnabled = extractBoolValue(from: unescapedLastChange, forTag: "SubEnabled")
        
        // Extract dialog and surround settings
        let dialogLevel = extractIntValue(from: unescapedLastChange, forTag: "DialogLevel")
        let speechEnhanceEnabled = extractBoolValue(from: unescapedLastChange, forTag: "SpeechEnhance")
        let surroundLevel = extractIntValue(from: unescapedLastChange, forTag: "SurroundLevel")
        let musicSurroundLevel = extractIntValue(from: unescapedLastChange, forTag: "MusicSurroundLevel")
        
        // Extract delay settings
        let audioDelay = extractIntValue(from: unescapedLastChange, forTag: "AudioDelay")
        
        // Extract mode settings
        let nightMode = extractBoolValue(from: unescapedLastChange, forTag: "NightMode")
        let surroundEnabled = extractBoolValue(from: unescapedLastChange, forTag: "SurroundEnabled")
        let surroundMode = extractIntValue(from: unescapedLastChange, forTag: "SurroundMode")
        
        // Extract additional settings
        let heightChannelLevel = extractIntValue(from: unescapedLastChange, forTag: "HeightChannelLevel")
        let sonarEnabled = extractBoolValue(from: unescapedLastChange, forTag: "SonarEnabled")
        let sonarCalibrationAvailable = extractBoolValue(from: unescapedLastChange, forTag: "SonarCalibrationAvailable")
        let presetNameList = extractValue(from: unescapedLastChange, forTag: "PresetNameList")
        
        return SonosRenderingControlEvent(
            masterVolume: masterVolume,
            masterMute: masterMute,
            bass: bass,
            treble: treble,
            loudness: loudness,
            outputFixed: outputFixed,
            speakerSize: speakerSize,
            subGain: subGain,
            subCrossover: subCrossover,
            subPolarity: subPolarity,
            subEnabled: subEnabled,
            dialogLevel: dialogLevel,
            speechEnhanceEnabled: speechEnhanceEnabled,
            surroundLevel: surroundLevel,
            musicSurroundLevel: musicSurroundLevel,
            audioDelay: audioDelay,
            nightMode: nightMode,
            surroundEnabled: surroundEnabled,
            surroundMode: surroundMode,
            heightChannelLevel: heightChannelLevel,
            sonarEnabled: sonarEnabled,
            sonarCalibrationAvailable: sonarCalibrationAvailable,
            presetNameList: presetNameList
        )
    }
    
    // Helper function to extract integer values with proper default handling
    private static func extractIntValue(from text: String, forTag tag: String) -> Int? {
        guard text.contains("<\(tag)") else {
            return nil  // Return nil if tag doesn't exist
        }
        
        return extractValue(from: text, forTag: tag)
            .flatMap { Int($0) }
    }
    
    // Helper function to extract boolean values with proper default handling
    private static func extractBoolValue(from text: String, forTag tag: String) -> Bool? {
        guard text.contains("<\(tag)") else {
            return nil  // Return nil if tag doesn't exist
        }
        
        return extractValue(from: text, forTag: tag)
            .map { $0 == "1" }
    }
    
    // Helper function to extract values from XML-like strings
    private static func extractValue(from text: String, forTag tag: String) -> String? {
        let pattern = "<\(tag) val=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
    
    // Helper function to parse track metadata
    private static func parseTrackMetaData(_ metadataString: String) -> SonosTrackMetadata? {
        guard let unescaped = metadataString.removingHTMLEntities() else { return nil }
        print(unescaped)
        // Extract values using simple pattern matching
        let title = extractValue(between: "<dc:title>", and: "</dc:title>", from: unescaped) ?? ""
        let creator = extractValue(between: "<dc:creator>", and: "</dc:creator>", from: unescaped) ?? ""
        let album = extractValue(between: "<upnp:album>", and: "</upnp:album>", from: unescaped) ?? ""
        let albumArtURI = extractValue(between: "<upnp:albumArtURI>", and: "</upnp:albumArtURI>", from: unescaped) ?? ""
        let streamInfoString = extractValue(between: "<r:streamInfo>", and: "</r:streamInfo>", from: unescaped) ?? ""

        return SonosTrackMetadata(
            title: title,
            creator: creator,
            album: album,
            albumArtURI: albumArtURI,
            streamInfo: SonosAudioStreamInfo.parse(from: streamInfoString)
        )
    }
    
    // Helper function to extract content between two strings
    private static func extractValue(between startTag: String, and endTag: String, from text: String) -> String? {
        guard let range = text.range(of: startTag)?.upperBound,
              let endRange = text[range...].range(of: endTag)?.lowerBound else {
            return nil
        }
        return String(text[range..<endRange])
    }
}
