import AppIntents
import SonosKit

struct SceneEntity: AppEntity, Codable {
    let id: UUID
    let name: String
    let description: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(
                stringLiteral: name
            ),
            image: DisplayRepresentation.Image(
                systemName: "bolt.fill"
            )
        )
    }

    static var defaultQuery = SceneQuery()
}
