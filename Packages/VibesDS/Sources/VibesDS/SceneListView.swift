import CloudStorage
import SwiftUI
import SonosKit

public struct SceneListView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    public init(scenes: [SonosScene]? = nil) {
        if let scenes {
            self.scenes = scenes
        }
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(scenes) { scene in
                    SceneButton(scene: scene) {
                        Task {
                            try? await sonosService.runScene(scene)
                        }
                    }
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
