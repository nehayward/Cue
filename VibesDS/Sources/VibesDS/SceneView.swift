import CloudStorage
import SwiftUI
import SonosKit

public struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    public init() {

    }

    public var body: some View {
        if scenes.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                HStack {
                    ForEach($scenes) { $scene in
                        SceneButton(scene: $scene) {
                            Task {
                                try? await sonosService.runScene(scene)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .fontDesign(.rounded)
                .fontWeight(.bold)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    SceneView()
        .environment(SonosService())
        .onAppear {
            @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
            scenes.append(SonosScene(id: UUID(), name: "Main", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 0)], isActive: false))
        }
}
