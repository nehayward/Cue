import AppIntents
import SonosKit
import Defaults
import CloudStorage

struct SceneQuery: EntityQuery {
    private static var sonosService = SonosService.shared
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    func entities(for identifiers: [UUID]) async throws -> [SceneEntity] {
        scenes.map { SceneEntity(id: $0.id, name: $0.name, description: $0.description) }
    }

    func suggestedEntities() async throws -> [SceneEntity] {
        scenes.map { SceneEntity(id: $0.id, name: $0.name, description: $0.description) }
    }

//    func defaultResult() async -> SceneEntity? {
//        try? await suggestedEntities().first
//    }
}
