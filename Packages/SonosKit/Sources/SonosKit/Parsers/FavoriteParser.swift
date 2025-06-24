import Foundation

final class FavoritesParser: NSObject, XMLParserDelegate {
    private var favorites: [PlayableContent] = []
    private var currentElement = ""
    private var isParsingResult = false
    
    // Current item state
    private var currentTitle = ""
    private var currentTrackID = ""
    private var currentURIMetadata = ""
    private var currentDescription = ""
    private var currentAlbumArtURI = ""
    
    // DIDL-Lite parsing state
    private var currentClass = ""
    private var tempElementContent = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "Result":
            isParsingResult = true
        case "item":
            // Reset item values
            currentTitle = ""
            currentTrackID = ""
            currentURIMetadata = ""
            currentDescription = ""
            currentAlbumArtURI = ""
            currentClass = ""
        default:
            tempElementContent = ""
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Result":
            isParsingResult = false
        case "item" where isParsingResult:
            // Create favorite content when item ends
            if !currentTitle.isEmpty && !currentTrackID.isEmpty {
                let contentType = ContentType(extractContentType(from: currentURIMetadata)) ?? .favorite
                var sonosAlbumArtURL: URL?
                if !currentAlbumArtURI.isEmpty {
                    sonosAlbumArtURL = URL(string: currentAlbumArtURI)
                }
                
                let isRadioStation = currentURIMetadata.contains("audioBroadcast") || currentURIMetadata.contains("radio")
                let mediaContent = MediaContent(service: .unknown, id: currentTrackID, type: contentType, location: nil)
                let metadata = PlayableContentMetadata(URIMetadata: currentURIMetadata.escaped.xmlAllowedString, radioStation: isRadioStation)
                
                let favorite = PlayableContent(
                    title: currentTitle,
                    subtitle: currentDescription,
                    thumbnail: sonosAlbumArtURL,
                    artwork: sonosAlbumArtURL,
                    content: mediaContent,
                    metadata: metadata
                )
                
                favorites.append(favorite)
            }
        case "dc:title" where isParsingResult:
            currentTitle = tempElementContent
        case "res" where isParsingResult:
            currentTrackID = tempElementContent.encodeProgramURI
        case "r:resMD" where isParsingResult:
            currentURIMetadata = tempElementContent
        case "r:description" where isParsingResult:
            currentDescription = tempElementContent
        case "upnp:albumArtURI" where isParsingResult:
            currentAlbumArtURI = tempElementContent
        case "upnp:class" where isParsingResult:
            currentClass = tempElementContent
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isParsingResult {
            tempElementContent += string
        }
    }
    
    func parse(xml: String) -> [PlayableContent] {
        favorites.removeAll()
        
        guard let data = xml.unescaped.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        
        return favorites
    }
    
    private func extractContentType(from didlXML: String) -> String {
        let pattern = "<upnp:class>([^<]+)</upnp:class>"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: didlXML, range: NSRange(didlXML.startIndex..., in: didlXML)) {
            let matchRange = Range(match.range(at: 1), in: didlXML)
            if let contentType = matchRange.map({ String(didlXML[$0]) }) {
                return contentType
            }
        }
        return ""
    }

}
