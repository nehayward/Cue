import CloudStorage
import SwiftUI
import SonosKit

public struct SceneListView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    
    private let sceneActivated: (SonosScene) -> ()

    public init(scenes: [SonosScene]? = nil, sceneActivated: @escaping (SonosScene) -> ()) {
        if let scenes {
            self.scenes = scenes
        }

        self.sceneActivated = sceneActivated
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(scenes) { scene in
                    SceneButton(scene: scene) {
                        sceneActivated(scene)
                        dismiss()
                        Task {
                            try? await sonosService.runScene(scene)
                        }
                    }
                    #if !os(watchOS)
                    .contentShape(.contextMenuPreview, Capsule())
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            scenes.removeAll { sceneSearch in
                                sceneSearch.id == scene.id
                            }
                        }
                    } preview: {
                        Text(scene.description)
                            .fontDesign(.rounded)
                            .padding()
                    }
                    #endif
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
    }
}

#Preview("Empty View") {
    SceneView()
        .environment(SonosService.shared)
}

#Preview("With Scenes") {
    var scenes: [SonosScene] = [SonosScene(id: UUID(), name: "Main", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 0)])]

    return SceneView(scenes: scenes)
        .environment(SonosService.shared)
}
