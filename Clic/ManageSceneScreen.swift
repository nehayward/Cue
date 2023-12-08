import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct ManageSceneScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    @State private var selectedScene: SonosScene?

    var body: some View {
        List {
            ForEach(scenes) { scene in
                HStack {
                    Text(scene.name)
                    Spacer()
                    Button {
                        scenes.removeAll { sceneSearch in
                            sceneSearch.id == scene.id
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
            .onMove(perform: moveItem)
        }
        .toolbar {
            EditButton()
        }
        .navigationTitle("Scenes")
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        scenes.move(fromOffsets: source, toOffset: destination)
    }
}

#Preview {
    NavigationStack {
        ManageSceneScreen(
            scenes: [
                SonosScene(
                    id: UUID(),
                    name: "Test 2",
                    rooms: [SceneRoom(
                        id: "",
                        ip: "",
                        name: "Garage",
                        volume: 10
                    )]
                ),
                SonosScene(
                    id: UUID(),
                    name: "😍",
                    rooms: [SceneRoom(
                        id: "",
                        ip: "",
                        name: "Garage",
                        volume: 10
                    )]
                )
            ]
        )
        .environment(SonosService())
        .padding()
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
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
