import Foundation

class ZoneGroupLiteParser {
    struct ZoneGroupState {
        let houseHoldID: String
        let thirdPartyMediaServers: String
        
        var houseHoldData: Data {
            Data(houseHoldID.utf8)
        }
    }
    
    static func parse(xmlString: String) -> ZoneGroupState? {
        // First, we need to decode the XML entities in the ZoneGroupState property
        guard let decodedXML = xmlString.removingPercentEncoding,
//              let zoneGroupStateRange = decodedXML.range(of: "<ZoneGroupState>.*?</ZoneGroupState>", options: .regularExpression),
              let museHouseholdIdRange = decodedXML.range(of: "<MuseHouseholdId>.*?</MuseHouseholdId>", options: .regularExpression),
              let thirdPartyMediaServersRange = decodedXML.range(of: "<ThirdPartyMediaServersX>.*?</ThirdPartyMediaServersX>", options: .regularExpression) else {
            
            // MARK: Improve this
//            print("❌ Failed to find required XML elements")
            return nil
        }
        
        // Extract the values
        let museHouseholdId = String(decodedXML[museHouseholdIdRange])
            .replacingOccurrences(of: "<MuseHouseholdId>", with: "")
            .replacingOccurrences(of: "</MuseHouseholdId>", with: "")
        
        let thirdPartyMediaServers = String(decodedXML[thirdPartyMediaServersRange])
            .replacingOccurrences(of: "<ThirdPartyMediaServersX>", with: "")
            .replacingOccurrences(of: "</ThirdPartyMediaServersX>", with: "")
        
        guard let houseHoldID = museHouseholdId.components(separatedBy: ".").first else {
            return nil
        }
        
//        print("📦 Parsed ZoneGroupState:")
//        print("🏠 MuseHouseholdId: \(museHouseholdId)")
//        print("🎵 ThirdPartyMediaServers: \(thirdPartyMediaServers)")
        
        return ZoneGroupState(
            houseHoldID: houseHoldID,
            thirdPartyMediaServers: thirdPartyMediaServers
        )
    }
} 
