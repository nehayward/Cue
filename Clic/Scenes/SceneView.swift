import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct SceneView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService

    @State var show: Bool = false
    @State var presentationDetentSelection: PresentationDetent = .medium

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(scenes) { scene in
                        SceneButton(scene: scene) {
                            dismiss()
                            alertService.showAlert(with: "Running \(scene.name)")
                            Task {
                                try? await sonosService.runScene(scene)
                            }
                        }
                        .padding(.horizontal, 12)
                        .contentShape(.contextMenuPreview, Capsule())
                        .contextMenu {
                            // TODO: Add
//                            Button("Edit") {
//                                Router.main.sheet(to: .editScene(scene))
//                            }
                            Button("Remove", role: .destructive) {
                                scenes.removeAll { sceneSearch in
                                    sceneSearch.id == scene.id
                                }
                            }
                        } preview: {
                            Text(scene.description)
                                .fontDesign(.rounded)
                                .padding()
                        }
                    }
                    if scenes.isEmpty {
                        ContentUnavailableView {
                            Label("Add Scene", systemImage: "bolt.fill")
                        } description: {
                            Text("Create a scene, to automate grouping and volume.")
                        } actions: {
                            NavigationLink {
                                SceneBuilderScreen()
                                    .onAppear {
                                        withAnimation {
                                            presentationDetentSelection = .large
                                        }
                                    }
                            } label: {
                                Label("Add Scene", systemImage: "plus.circle.fill")

                                //                            Button {
                                //                                HapticManager.shared.fireHaptic(.buttonPress)
                                //                                show = true
                                //                            } label: {
                                //                                    Image(systemName: "plus.circle.fill")
                                //                                        .font(.title)
                                //                            }
                                //                            .bold()
                                //                            .foregroundStyle(Color.accentColor.gradient)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        show = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Scene")
                            .bold()
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                }
            }
            .sheet(isPresented: $show) {
                NavigationStack {
                    SceneBuilderScreen()
                        .addDismiss {
                            dismiss()
                        }
                }
            }
            .addDismiss {
                dismiss()
            }
        }
        .presentationDetents([.medium, .large], selection: $presentationDetentSelection)
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    Text("")
        .sheet(isPresented: .constant(true)) {
            SceneView(
                scenes: [SonosScene(
                    id: UUID(),
                    name: "Garage",
                    rooms: [SceneRoom(
                        id: "",
                        ip: "",
                        name: "Garage",
                        volume: 10
                    )],
                    playableContent: PlayableContent(
                        title: "Cold Heart - PNAU Remix",
                        subtitle: "Elton John, Dua Lipa, PNAU",
                        thumbnail: URL(
                            string: "https://i.scdn.co/image/ab67616d00004851523458c391fe8180a19a1069"
                        ),
                        artwork: URL(
                            string: "https://i.scdn.co/image/ab67616d0000b273523458c391fe8180a19a1069"
                        ),
                        content: MediaContent(service: MusicService.spotify, id: "7rglLriMNBPAyuJOMGwi39", type: .track, location: URL(string:"https://open.spotify.com/track/7rglLriMNBPAyuJOMGwi39"))
                    )
                )]
            )
            .environment(SonosService())
            .environment(AlertService())
            .padding()
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
}

#Preview("Empty") {
    SceneView(
        scenes: []
    )
    .environment(SonosService())
    .environment(AlertService())
    .padding()
}
