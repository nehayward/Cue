import CloudStorage
import SwiftUI
import SonosKit

struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var show: Bool = false

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(scenes) { scene in
                    Button {
                        Task {
                            await sonosService.runScene(scene)
                        }
                    } label: {
                        Text(scene.name)
                            .padding(12)
                            .background{
                                Capsule()
                                    .foregroundStyle(.thinMaterial)
                                    .shadow(radius: 2, x: 0, y: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.capsule)
                    .contentShape(.contextMenuPreview, Capsule())
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            scenes.removeAll { sceneSearch in
                                sceneSearch.id == scene.id
                            }
                        }
                    }
                }
                .padding(.vertical)
                .background(.clear)
            }
            .background(.clear)
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.trailing, 40, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .mask(alignment: .trailing) {
            LinearGradient(stops: [.init(color: Color.black.opacity(0), location: -0.1), .init(color: Color.black, location: 0.1), .init(color: Color.black, location: 0.85), .init(color: Color.black.opacity(0), location: 0.9)], startPoint: .leading, endPoint: .trailing)
        }
        .safeAreaInset(edge: .trailing) {
            if scenes.isEmpty {
                Button {
                    show = true
                } label: {
                    Label("Add Scene", systemImage: "plus.circle.fill")
                        .padding(4)
                }
                .bold()
                .buttonBorderShape(.capsule)
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    show = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                }
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
