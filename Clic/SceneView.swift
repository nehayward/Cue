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
                        .contentShape(.contextMenuPreview, Capsule())
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                scenes.removeAll { sceneSearch in
                                    sceneSearch.id == scene.id
                                }
                            }
                        }
                    }
                    if scenes.isEmpty {
                        ContentUnavailableView {
                            Label("Add Scene", systemImage: "wand.and.stars.inverse")
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
                    } else {
                        NavigationLink {
                            SceneBuilderScreen()
                                .onAppear {
                                    withAnimation {
                                        presentationDetentSelection = .large
                                    }
                                }
                        } label: {
                            //                            Button {
                            //                                HapticManager.shared.fireHaptic(.buttonPress)
                            //                                show = true
                            //                            } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                            //                            }
                            //                            .bold()
                            //                            .foregroundStyle(Color.accentColor.gradient)
                        }
                    }
                }
                .fontDesign(.rounded)
                .fontWeight(.bold)
            }
            .contentMargins(.leading, 12, for: .scrollContent)
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            //            .navigationDestination(for: Set<String>.self) { ids in
            //                SceneBuilderScreen(sheetDestination: .constant(nil))
            //            }
            //            .sheet(isPresented: $show) {
            //                NavigationStack {
            //                    SceneBuilderScreen(sheetDestination: .constant(nil))
            //                        .addDismiss {
            //                            dismiss()
            //                        }
            //                }
            //            }
            .addDismiss {
                dismiss()
            }
        }
        .presentationDetents([.medium, .large], selection: $presentationDetentSelection)
        .presentationBackground(.ultraThinMaterial.secondary)
        .presentationDragIndicator(.hidden)

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
