import AppIntents
import SonosKit

struct SonosDeviceEntity: AppEntity, Identifiable, Codable {
    var id: String
    var name: String
    var ip: String
    var volume: Double

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sonos Device"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(stringLiteral: name)
    }

    static var defaultQuery = SonosDeviceQuery()
}
