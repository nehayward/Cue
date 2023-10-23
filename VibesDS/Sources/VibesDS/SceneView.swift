import CloudStorage
import SwiftUI
import SonosKit

public struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    public init() { }

    public var body: some View {
        if scenes.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(scenes) { scene in
                        Button {
                            Task {
                                await sonosService.runScene(scene)
                            }
                        } label: {
                            Text(scene.name)
//                                .padding()
//                                .background{
//                                    Capsule()
//                                        .foregroundStyle(.regularMaterial)
//                                        .shadow(radius: 2, x: 0, y: 1)
//                                }
//                                .padding(2)
                        }
                        .buttonBorderShape(.capsule)
                        .buttonStyle(.bordered)
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
//    [SonosScene(id: UUID(), name: "Garage", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 20)])]
    SceneView()
        .environment(SonosService())
}
