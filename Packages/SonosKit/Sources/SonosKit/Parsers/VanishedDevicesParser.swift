import Foundation

final class VanishedDevicesParser: NSObject, XMLParserDelegate {
    var vanishedDevices: [VanishedDevice] = []
    private var insideVanishedDevices = false
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    func parse(xml: String) -> [VanishedDevice] {
        let xmlData = xml.unescaped.ampersandSafe.data(using: .utf8)!
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.parse()
        return vanishedDevices
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "VanishedDevices" {
            insideVanishedDevices = true
            return
        }

        guard insideVanishedDevices, elementName == "Device" else { return }
        guard let id = attributeDict["UUID"] else { return }

        let name = (attributeDict["ZoneName"] ?? "").replacingOccurrences(of: "%26", with: "&")
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

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "VanishedDevices" {
            insideVanishedDevices = false
        }
    }
}
