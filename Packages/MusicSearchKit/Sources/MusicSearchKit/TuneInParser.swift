import Foundation
import SWXMLHash

public final class TuneInParser: Sendable {
    func parseStations(xmlData: Data) -> [TuneInStation] {
        let xml = XMLHash.parse(xmlData)
        return xml["opml"]["body"].children.map { station(from: $0) }
    }

    /// A browse page: stations, links to further pages, and titled groups
    /// of either. Groups nest (a local page is "FM" and "AM" blocks of
    /// stations), so this recurses through untyped outlines.
    func parseBrowse(xmlData: Data) -> [TuneInBrowseItem] {
        let xml = XMLHash.parse(xmlData)
        return browseItems(in: xml["opml"]["body"])
    }

    private func browseItems(in node: XMLIndexer) -> [TuneInBrowseItem] {
        node.children.compactMap { outline -> TuneInBrowseItem? in
            let type: String? = outline.value(ofAttribute: "type")
            let title: String = outline.value(ofAttribute: "text") ?? ""

            switch type {
            case "audio":
                // Shows and podcast episodes are audio outlines too; only a
                // station plays as a stream on Sonos.
                let item: String? = outline.value(ofAttribute: "item")
                guard item == nil || item == "station" else { return nil }
                let station = station(from: outline)
                guard !station.id.isEmpty else { return nil }
                return .station(station)
            case "link":
                guard let urlString: String = outline.value(ofAttribute: "URL"),
                      let url = Self.secured(URL(string: urlString)),
                      !title.isEmpty else { return nil }
                return .link(TuneInBrowseLink(title: title, guideID: outline.value(ofAttribute: "guide_id"), url: url))
            default:
                let items = browseItems(in: outline)
                guard !items.isEmpty, !title.isEmpty else { return nil }
                return .group(TuneInBrowseGroup(title: title, items: items))
            }
        }
    }

    /// Browse links come back over plain HTTP, which App Transport Security
    /// refuses; the host serves the same pages over HTTPS.
    static func secured(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.scheme == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    /// One station outline, from a search result or a browse page. The
    /// caption is what's on air when TuneIn says so, else the station's own
    /// tagline (`subtext`), which is all a browse page carries.
    private func station(from outline: XMLIndexer) -> TuneInStation {
        let imageURL = (outline.value(ofAttribute: "image") ?? "").replacingOccurrences(of: "logoq.png", with: "logod.png")

        let playingTrack: String? = outline.value(ofAttribute: "playing")
        let track: String? = outline.value(ofAttribute: "current_track")
        let subtext: String? = outline.value(ofAttribute: "subtext")
        let stationName: String = outline.value(ofAttribute: "text") ?? ""

        return TuneInStation(
            title: stationName,
            id: outline.value(ofAttribute: "guide_id") ?? "",
            currentTrack: track ?? "",
            imageURL: URL(string: imageURL),
            url: URL(string: outline.value(ofAttribute: "URL") ?? ""),
            stationInfo: .init(
                name: stationName,
                song: [playingTrack, track, subtext].compactMap { $0 }.first { !$0.isEmpty },
                album: nil,
                artist: nil,
                location: nil
            )
        )
    }

    func parseStationDetails(xmlData: Data) -> TuneInStation {
        let xml = XMLHash.parse(xmlData)
        let stationXML = xml["opml"]["body"]["outline"]["station"]
        let imageURL = stationXML["logo"].element?.text.replacingOccurrences(of: "logoq", with: "logod") ?? ""

        let station = TuneInStation(
                title: stationXML["name"].element?.text ?? "",
                id: stationXML["guide_id"].element?.text ?? "",
                currentTrack: stationXML["current_song"].element?.text ?? "",
                imageURL: URL(string: imageURL),
                url: URL(string: stationXML["tunein_url"].element?.text ?? ""),
                stationInfo: .init(
                    name: stationXML["name"].element?.text ?? "",
                    song: stationXML["current_song"].element?.text,
                    album: stationXML["current_album"].element?.text,
                    artist: stationXML["current_artist"].element?.text,
                    location: URL(string: stationXML["tunein_url"].element?.text ?? "")
                )
            )
        return station
    }

    /// Where a described station is: its `latlon`, else a `latitude` and
    /// `longitude` of their own, and the place it names. Nil when the
    /// answer holds no station at all (an error page), which says nothing
    /// about where the station is; a station with no place comes back
    /// empty instead.
    func parsePlace(xmlData: Data) -> TuneInPlace? {
        let xml = XMLHash.parse(xmlData)
        let stationXML = xml["opml"]["body"]["outline"]["station"]
        guard stationXML.element != nil else { return nil }

        func text(_ name: String) -> String? {
            guard let text = stationXML[name].element?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return text
        }

        var place = TuneInPlace(location: text("location"))
        if let point = text("latlon").flatMap(TuneInPlace.coordinate(fromLatLon:))
            ?? TuneInPlace.coordinate(fromLatLon: [text("latitude"), text("longitude")].compactMap { $0 }.joined(separator: ",")) {
            place.latitude = point.latitude
            place.longitude = point.longitude
        }
        return place
    }
}
