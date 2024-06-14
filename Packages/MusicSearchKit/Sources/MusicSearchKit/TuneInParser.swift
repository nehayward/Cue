import Foundation
import SWXMLHash

public final class TuneInParser {
    func parseStations(xmlData: Data) -> [TuneInStation] {
        let xml = XMLHash.parse(xmlData)
        let stations: [TuneInStation] = xml["opml"]["body"].children.compactMap { hub in
            let imageURL = (hub.value(ofAttribute: "image") ?? "").replacingOccurrences(of: "logoq.png", with: "logod.png")

            let playingTrack: String? = hub.value(ofAttribute: "playing")
            let track: String? = hub.value(ofAttribute: "current_track")
            let stationName: String = hub.value(ofAttribute: "text") ?? ""

            return TuneInStation(
                title: hub.value(ofAttribute: "text") ?? "" ,
                id: hub.value(ofAttribute: "guide_id") ?? "",
                currentTrack: hub.value(ofAttribute: "current_track") ?? "",
                imageURL: URL(string: imageURL),
                url: URL(string: hub.value(ofAttribute: "URL") ?? ""),
                stationInfo: .init(name: stationName, song: [playingTrack, track].compactMap { $0 }.first, album: nil, artist: nil, location: nil)
            )
        }
        return stations
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

}
