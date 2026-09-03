import AppIntents
import CloudStorage
import SonosKit
import SwiftUI

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Scene"
    static var isDiscoverable: Bool = true
    static var description = IntentDescription(
        "Create a Scene in Cue to group speakers, set volume, and play music",
        categoryName: "Scenes"
    )
    
    @CloudStorage("com.cue.scenes") private var scenes: [SonosScene] = []
    @Parameter(title: "Scene", default: nil) var scene: SceneEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$scene)")
    }

    init() { }

    func perform() async throws -> some ShowsSnippetView {
        guard CloudStorageSync.shared.bool(for: "com.cue.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Cue")
        }

        let resolvedScene: SceneEntity
        if let existingScene = scene {
            resolvedScene = existingScene
        } else {
            resolvedScene = try await $scene.requestDisambiguation(among: scenes.map { SceneEntity(id: $0.id, name: $0.name, description: $0.description) })
        }

        guard let foundScene = scenes.first(where: { $0.id == resolvedScene.id }) else {
            throw IntentError.message("Scene doesn't exist")
        }

        try await SonosService.shared.runScene(foundScene)
        return .result(view: resultView(foundScene))
    }
    
    private func resultView(_ scene: SonosScene) -> some View {
        Text("\(scene.description)").multilineTextAlignment(.center).fontDesign(.rounded)
    }
}



#if !os(visionOS)
@available(iOS 18.0, *)
extension RunSceneIntent: ControlConfigurationIntent { }
#endif
