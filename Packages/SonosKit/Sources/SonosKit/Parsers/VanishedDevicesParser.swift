import Foundation

class VanishedDevicesParser: NSObject, XMLParserDelegate {
    var vanishedDevices: [VanishedDevice] = []
    private var currentElement = ""
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "VanishedDevices" {
            guard let id = attributeDict["UUID"] else { return }
            
            let name = attributeDict["ZoneName"]
            let lastKnownIP = attributeDict["LastKnownIP"]
            let date = dateFormatter.date(from: attributeDict["LastSeenUTC"] ?? "")
            let reason = attributeDict["Reason"]
            let info = attributeDict["MoreInfo"]
            let macAddress = attributeDict["Mac"]
            
            let device = VanishedDevice(
                id: id,
                name: name,
                reason: reason,
                IP: lastKnownIP,
                lastSeen: date,
                info: info,
                macAddress: macAddress
            )
            
            vanishedDevices.append(device)
        }
    }
}
