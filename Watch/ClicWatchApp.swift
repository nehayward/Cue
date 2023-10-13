import Observation
import SwiftUI
import SonosKit
import WidgetKit
import CloudStorage

@main
struct ClicWatchApp: App {
    @Environment(\.scenePhase) var scenePhase

    @State var sonosService = SonosService()
    @State var popover = Popover()

    @State var selected: String?

    var body: some Scene {
        WindowGroup {
            DeviceListView(selected: $selected)
                .environment(popover)
                .environment(sonosService)
                .onChange(of: selected) {
                    print("Update current")
                    if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                        sonosService.selectedGroup = sonosService.sorted[index]
                    }
                }

            //                .overlay(alignment: .top) {
            //                    VStack(spacing: 0) {
            //                        Text("\(ip ?? "")")
            //                            .fontDesign(.rounded)
            //                            .fontWidth(.compressed)
            //                            .font(.caption2)
            //                            .foregroundStyle(Color.accentColor.gradient)
            //                            .background(.thickMaterial)
            //                            .clipShape(Capsule())
            //                            .ignoresSafeArea(edges: .top)
            //                        Text("\(sonosService.lastKnownIP)")
            //                            .fontDesign(.rounded)
            //                            .fontWidth(.compressed)
            //                            .font(.caption2)
            //                            .foregroundStyle(Color.accentColor.gradient)
            //                            .background(.thickMaterial)
            //                            .clipShape(Capsule())
            //                            .ignoresSafeArea(edges: .top)
            //                    }
            //                }
            
            //                .overlay(alignment: .top) {
            //                    Text(sonosService.lastKnownIP)
            //                        .padding()
            //                        .background {
            //                            Capsule()
            //                                .foregroundStyle(.thinMaterial)
            //                        }
            //                }
            
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
    }
    
    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitorWatch(useCache: true)
            
            Task {
                try? await sonosService.updateGroupsCheckPlayback()
                
                if selected == nil {
                    let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
                    if playingGroups.count == 1, let groupPlaying = playingGroups.first {
                        try await Task.sleep(for: .milliseconds(200))
                        //                        alertService.showAlert(with: "Jumped to \(groupPlaying.coordinatorRoom.name)")
                        selected = groupPlaying.coordinatorID
                    }
                }
            }
        case .inactive:
            print("Inactive")
        case .background:
            print("Background")
            Task {
                sonosService.sonosPulse.cancel()
            }
        @unknown default:
            break
        }
    }
}
