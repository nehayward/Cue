import Foundation
import SWXMLHash

public final class TuneInParser {
    func parseXML(xmlData: Data) -> TuneInResults? {
        let xml = XMLHash.parse(xmlData)
        
        return nil
    }

}
