import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct ManageSceneScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    @State private var sceneToDelete: SonosScene?

    var body: some View {
        List {
            ForEach(scenes) { scene in
                HStack {
                    Text(scene.name)
                    Spacer()
                    Button(role: .destructive) {
                        sceneToDelete = scene
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
        .confirmationDialog(
            "Delete Scene",
            isPresented: .constant(sceneToDelete != nil),
            presenting: sceneToDelete
        ) { scene in
            Button("Delete '\(scene.name)'", role: .destructive) {
                scenes.removeAll { sceneSearch in
                    sceneSearch.id == scene.id
                }
                sceneToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sceneToDelete = nil
            }
        } message: { scene in
            Text("Are you sure you want to delete the scene '\(scene.name)'? This action cannot be undone.")
        }
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
