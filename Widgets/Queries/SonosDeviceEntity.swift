import AppIntents
import SonosKit

struct SonosDeviceEntity: AppEntity, Identifiable, Codable {
    let id: String
    let name: String
    let ip: String
    let volume: Double

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sonos Device"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(stringLiteral: name)
    }

    static var defaultQuery = SonosDeviceQuery()
}
