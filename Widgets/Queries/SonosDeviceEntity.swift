import AppIntents
import CoreSpotlight
import SonosKit

struct SonosDeviceEntity: AppEntity, Identifiable, Codable, IndexedEntity {
    let id: String
    let ip: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sonos Device"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(
                stringLiteral: name
            ),
            image: DisplayRepresentation.Image(
                systemName: "hifispeaker.fill"
            )
        )
    }

    static var defaultQuery = SonosDeviceQuery()
}

extension SonosDeviceEntity {
    var toRoom: Room {
       Room(id: id, ip: ip, name: name)
    }
}
