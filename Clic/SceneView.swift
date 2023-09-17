import CloudStorage
import SwiftUI
import SonosKit

struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var show: Bool = false

    @CloudStorage("com.clic.scenes")
    var scenes: [SonosScene] = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(scenes) { scene in
                    Button {
                        Task {
                            await sonosService.runScene(scene)
                        }
                    } label: {
                        Text(scene.name)
                            .padding()
                            .background{
                                Capsule()
                                    .foregroundStyle(.thinMaterial)
                                    .shadow(radius: 2, x: 0, y: 1)
                            }
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .trailing) {
            Button {
                show = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
            }
        }
        .sheet(isPresented: $show) {
            SceneBuilderScreen()
        }
    }
}

#Preview {
    SceneView(scenes: [SonosScene(id: UUID(), name: "Test", rooms: [])])
        .environment(SonosService())
}
