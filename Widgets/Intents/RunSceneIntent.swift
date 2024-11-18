import AppIntents
import CloudStorage
import SonosKit
import SwiftUI

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Scene"
    static var isDiscoverable: Bool = true
    
    @CloudStorage("com.clic.scenes") private var scenes: [SonosScene] = []
    
    @Parameter(title: "Scene", default: nil) var scene: SceneEntity?
    @Parameter(title: "Always Ask", default: false) var askForScene: Bool
   
    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$scene)")
    }
    
    init() { }
    
    init(askForScene: Bool) {
        self.askForScene = askForScene
    }

    func perform() async throws -> some ShowsSnippetView {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }
        
        if askForScene {
            let newScene = try await $scene.requestDisambiguation(among: scenes.map{ SceneEntity(id: $0.id, name: $0.name, description: $0.description) } )
            guard let foundScene = scenes.first(where: { $0.id == newScene.id }) else {
                throw IntentError.message("Scene doesn't exist")
            }

            try await SonosService.shared.runScene(foundScene)
            return .result(view: resultView(foundScene))
        }
        
        guard let scene else {
            let newScene = try await $scene.requestDisambiguation(among: scenes.map{ SceneEntity(id: $0.id, name: $0.name, description: $0.description) } )
            guard let foundScene = scenes.first(where: { $0.id == newScene.id }) else {
                throw IntentError.message("Scene doesn't exist")
            }

            try await SonosService.shared.runScene(foundScene)
            return .result(view: resultView(foundScene))
        }

        
        guard let foundScene = scenes.first(where: { $0.id == scene.id }) else {
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
