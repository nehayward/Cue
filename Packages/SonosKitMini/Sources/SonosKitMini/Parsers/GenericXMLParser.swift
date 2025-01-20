import Foundation

class GenericXMLParser: NSObject, XMLParserDelegate {
    private var targetElement: String
    private var currentElement = ""
    private var foundValue: String?
    
    init(targetElement: String) {
        self.targetElement = targetElement
    }
    
    func parseXML(_ xmlString: String) -> String? {
        guard let data = xmlString.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? foundValue : nil
    }
    
    // MARK: - XMLParserDelegate Methods
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == targetElement {
            foundValue = (foundValue ?? "") + string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == targetElement {
            currentElement = ""
        }
    }
}
