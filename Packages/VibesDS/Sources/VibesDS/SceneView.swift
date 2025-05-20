import CloudStorage
import Defaults
import SwiftUI
import SonosKit

public struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []

    public init(scenes: [SonosScene]? = nil) {
        if let scenes {
            self.scenes = scenes
        }
    }

    public var body: some View {
        NavigationStack {
            if scenes.isEmpty {
                Text("Create a scene on your phone.")
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading) {
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
                #if !os(tvOS)
                .scrollContentBackground(.hidden)
                #endif
            }
        }
    }
}

#Preview("Empty View") {
    SceneView()
        .environment(SonosService())
}

#Preview("With Scenes") {
    var scenes: [SonosScene] = [SonosScene(id: UUID(), name: "Main", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 0)])]

    return SceneView(scenes: scenes)
        .environment(SonosService())
}
