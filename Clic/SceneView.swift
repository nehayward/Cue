import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService: AlertService

    @State var show: Bool = false

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach($scenes) { $scene in
                    SceneButton(scene: $scene) {
                        alertService.showAlert(with: "Running \(scene.name)")
                        Task {
                            try? await sonosService.runScene(scene)
                        }
                    }
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
                if scenes.isEmpty {
                    Button {
                        show = true
                    } label: {
                        Label("Add Scene", systemImage: "plus.circle.fill")
                            .padding(12)
                            .background{
                                Capsule()
                                    .foregroundStyle(.thinMaterial)
                                    .shadow(radius: 2, x: 0, y: 1)
                            }
                    }
                    .buttonStyle(.haptic)
                    .bold()
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        show = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.haptic)
                    .bold()
                    .foregroundStyle(Color.accentColor.gradient)
                }
            }
            .background(.clear)
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.leading, 12, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(.bar)
        .sheet(isPresented: $show) {
            NavigationStack {
                SceneBuilderScreen(sheetDestination: .constant(nil))
            }
        }

    }
}

#Preview {
    SceneView(
        scenes: [SonosScene(
            id: UUID(),
            name: "Test",
            rooms: [SceneRoom(
                id: "",
                ip: "",
                name: "Garage",
                volume: 10
            )]
        )]
    )
    .environment(SonosService())
    .environment(AlertService())
    .padding()
    .frame(maxHeight: .infinity, alignment: .bottom)
}

#Preview {
    SceneView(
        scenes: []
    )
    .environment(SonosService())
    .environment(AlertService())
    .padding()
}

#Preview("Empty") {
    SceneView(scenes: [])
        .environment(SonosService())
        .environment(AlertService())
}
