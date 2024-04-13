import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(\.dismiss) var dismiss

    @State var show: Bool = false

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
//    @State private var path: [Set<String>] = []

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(scenes) { scene in
                        SceneButton(scene: scene) {
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
                    if scenes.isEmpty {
                        ContentUnavailableView {
                            Label("Add Scene", systemImage: "wand.and.stars.inverse")
                        } description: {
                            Text("Create a scene, to automate grouping and volume.")
                        } actions: {
                            NavigationLink {
                                SceneBuilderScreen(sheetDestination: .constant(nil))
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
                            SceneBuilderScreen(sheetDestination: .constant(nil))
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
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial.secondary)
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
