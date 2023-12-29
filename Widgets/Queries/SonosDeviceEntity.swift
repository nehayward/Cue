import AppIntents
import SonosKit

struct SonosDeviceEntity: AppEntity, Identifiable, Codable {
    let id: String
    let ip: String
    let name: String
    let volume: Double

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sonos Device"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name), image: DisplayRepresentation.Image(systemName: "hifispeaker"))
    }

    static var defaultQuery = SonosDeviceQuery()
}
