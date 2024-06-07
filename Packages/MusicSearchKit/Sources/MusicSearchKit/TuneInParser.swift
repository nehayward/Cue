import Foundation
import SWXMLHash

public final class TuneInParser {
    func parseStations(xmlData: Data) -> [TuneInStation] {
        let xml = XMLHash.parse(xmlData)
        let tracks: [TuneInStation] = xml["opml"]["body"].all.compactMap { hub in
            TuneInStation(title: hub.value(ofAttribute: "text") ?? "" )
        }
        return tracks
    }

}
