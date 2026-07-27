import Foundation

/// Parses SMAPI `getMetadataResponse` / `searchResponse` SOAP bodies into
/// `SMAPIMediaResult`. Handles both `mediaCollection` (containers) and
/// `mediaMetadata` (playable items), including the nested `trackMetadata`
/// element where track artist/album/art live.
///
/// Note: the SOAP response double-encodes the result, but Sonos services
/// return the metadata as real child elements (not escaped), so a streaming
/// `XMLParser` over the whole envelope is sufficient.
public final class SMAPIMediaParser: NSObject, XMLParserDelegate {
    private var items: [SMAPIMediaItem] = []
    private var index = 0
    private var count = 0
    private var total = 0

    // Current element scanning state
    private var currentElement = ""
    private var text = ""

    // Current item under construction
    private var inItem = false
    private var isContainer = false
    private var id = ""
    private var itemType = ""
    private var title = ""
    private var summary: String?
    private var artist: String?
    private var album: String?
    private var albumArtURI: String?
    private var mimeType: String?
    private var canPlay = false
    private var canEnumerate = false

    public static func parse(xml: String) -> SMAPIMediaResult? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let parser = SMAPIMediaParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return SMAPIMediaResult(
            index: parser.index,
            count: parser.count > 0 ? parser.count : parser.items.count,
            total: parser.total > 0 ? parser.total : parser.items.count,
            items: parser.items
        )
    }

    // MARK: - XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?,
                       attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName)
        currentElement = name
        text = ""

        switch name {
        case "mediaCollection":
            beginItem(container: true)
        case "mediaMetadata":
            beginItem(container: false)
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "mediaCollection", "mediaMetadata":
            endItem()
        case "index" where !inItem:
            index = Int(value) ?? 0
        case "count" where !inItem:
            count = Int(value) ?? 0
        case "total" where !inItem:
            total = Int(value) ?? 0
        case "id" where inItem && id.isEmpty:
            id = value
        case "itemType" where inItem:
            itemType = value
        case "title" where inItem && title.isEmpty:
            title = value
        case "summary" where inItem:
            summary = value.isEmpty ? summary : value
        case "artist" where inItem:
            artist = value.isEmpty ? artist : value
        case "album" where inItem:
            album = value.isEmpty ? album : value
        case "albumArtURI" where inItem:
            albumArtURI = value.isEmpty ? albumArtURI : value
        // Radio streams expose artwork as <streamMetadata><logo>…</logo>.
        case "logo" where inItem:
            albumArtURI = albumArtURI ?? (value.isEmpty ? nil : value)
        case "mimeType" where inItem:
            mimeType = value.isEmpty ? mimeType : value
        case "canPlay" where inItem:
            canPlay = (value as NSString).boolValue
        case "canEnumerate" where inItem:
            canEnumerate = (value as NSString).boolValue
        default:
            break
        }
        text = ""
    }

    // MARK: - Helpers

    private func beginItem(container: Bool) {
        inItem = true
        isContainer = container
        id = ""
        itemType = ""
        title = ""
        summary = nil
        artist = nil
        album = nil
        albumArtURI = nil
        mimeType = nil
        // Containers can usually be enumerated; playable items can usually play.
        canPlay = !container
        canEnumerate = container
    }

    private func endItem() {
        guard inItem, !id.isEmpty else {
            inItem = false
            return
        }
        items.append(
            SMAPIMediaItem(
                id: id,
                itemType: itemType,
                title: title,
                summary: summary,
                artist: artist,
                album: album,
                albumArtURI: albumArtURI,
                mimeType: mimeType,
                isContainer: isContainer,
                canPlay: canPlay,
                canEnumerate: canEnumerate
            )
        )
        inItem = false
    }

    /// Strips any namespace prefix (e.g. `ns:title` -> `title`).
    private func localName(_ element: String) -> String {
        guard let colon = element.firstIndex(of: ":") else { return element }
        return String(element[element.index(after: colon)...])
    }
}
