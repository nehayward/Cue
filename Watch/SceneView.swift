import CloudStorage
import Defaults
import SwiftUI
import VibesDS
import SonosKitMini

public struct SceneView: View {
    @Environment(SonosMiniService.self) var sonosService
    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []
    @Environment(\.dismiss) var dismiss

    public var body: some View {
        NavigationStack {
            if scenes.isEmpty {
                Text("Create a Scene on your phone.")
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading) {
                        ForEach(scenes) { scene in
                            Button {
                                Task {      
                                    try? await sonosService.runScene(scene)
                                    dismiss()
                                    try? await sonosService.loadWatch(useCache: true)
                                }
                            } label: {
                                Text(scene.name)
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
    }
}

//
//#Preview("Empty View") {
//    SceneView()
//        .environment(SonosService())
//}
//
//#Preview("With Scenes") {
//    var scenes: [SonosScene] = [SonosScene(id: UUID(), name: "Main", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 0)])]
//
//    return SceneView(scenes: scenes)
//        .environment(SonosService())
//}
