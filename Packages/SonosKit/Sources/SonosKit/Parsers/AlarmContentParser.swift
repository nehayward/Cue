import Foundation

final class AlarmContentParser: NSObject, XMLParserDelegate {
    
    struct ContentInfo {
        let id: String
        let name: String
        let type: String
    }
    
    var contentInfo: ContentInfo?
    private var currentElement = ""
    private var currentName = ""
    private var currentType = ""
    private var currentId = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item", let id = attributeDict["id"] {
            currentId = id
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "dc:title":
            currentName += string
        case "upnp:class":
            currentType += string
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            contentInfo = ContentInfo(
                id: currentId.trimmingCharacters(in: .whitespacesAndNewlines),
                name: currentName.trimmingCharacters(in: .whitespacesAndNewlines),
                type: currentType.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
