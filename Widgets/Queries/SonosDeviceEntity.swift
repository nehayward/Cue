import AppIntents
import CoreSpotlight
import SonosKit

struct SonosDeviceEntity: AppEntity, Identifiable, Codable, IndexedEntity {
    let id: String
    let ip: String
    let name: String
    /// Which speech-enhancement control this speaker has, resolved from its model
    /// when the entity was built, so intents don't have to ask the speaker.
    /// `nil` means unknown — including entities saved into a shortcut before this
    /// existed — and callers should probe rather than assume.
    let isArcUltra: Bool?

    init(id: String, ip: String, name: String, isArcUltra: Bool? = nil) {
        self.id = id
        self.ip = ip
        self.name = name
        self.isArcUltra = isArcUltra
    }

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
