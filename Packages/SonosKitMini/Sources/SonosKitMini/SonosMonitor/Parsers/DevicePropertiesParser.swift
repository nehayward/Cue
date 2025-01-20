//
//  DevicePropertiesParser.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 1/14/25.
//


import Foundation

final class DevicePropertiesParser {
    typealias Event = SonosDevicePropertiesEvent
    
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
        
        print(xmlString)
        let name = properties["ZoneName"]
        
        var battery: Battery?
        if let info = properties["MoreInfo"] {
            battery = Battery(info: info)
        }
        
        return Event(name: name, battery: battery)
    }
}
