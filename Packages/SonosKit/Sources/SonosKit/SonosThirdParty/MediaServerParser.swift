//
//  MediaServerParser.swift
//  Listener
//
//  Created by Nick Hayward on 6/13/25.
//


import Foundation

class MediaServerParser {
    static func parse(xmlString: String) -> [MediaServer] {
        var servers: [MediaServer] = []
        
        // Split the XML string into individual service entries
        let serviceEntries = xmlString.components(separatedBy: "<Service")
            .filter { $0.contains("UDN=") }
        
        for entry in serviceEntries {
            if let server = parseServiceEntry(entry) {
                servers.append(server)
            }
        }
        
        return servers
    }
    
    private static func parseServiceEntry(_ entry: String) -> MediaServer? {
        // Extract attributes using regex
        let udnPattern = "UDN=\"([^\"]+)\""
        let nicknamePattern = "Nickname0=\"([^\"]+)\""
        let tokenPattern = "Token0=\"([^\"]+)\""
        let keyPattern = "Key0=\"([^\"]+)\""
        let serialNumPattern = "SerialNum0=\"([^\"]+)\""
        let flagsPattern = "Flags0=\"([^\"]+)\""
        let tierPattern = "Tier0=\"([^\"]+)\""
        
        guard let udn = extractValue(from: entry, pattern: udnPattern),
              let nickname = extractValue(from: entry, pattern: nicknamePattern),
              let token = extractValue(from: entry, pattern: tokenPattern),
              let key = extractValue(from: entry, pattern: keyPattern),
              let serialNumStr = extractValue(from: entry, pattern: serialNumPattern),
              let flagsStr = extractValue(from: entry, pattern: flagsPattern),
              let tierStr = extractValue(from: entry, pattern: tierPattern),
              let serialNum = Int(serialNumStr),
              let flags = Int(flagsStr),
              let tier = Int(tierStr) else {
            return nil
        }
        
        return MediaServer(
            udn: udn,
            nickname: nickname,
            token: token,
            key: key,
            serialNum: serialNum,
            flags: flags,
            tier: tier
        )
    }
    
    private static func extractValue(from string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
} 
