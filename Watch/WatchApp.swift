import Observation
import SwiftUI
import SonosKit
import WidgetKit
import CloudStorage

@main
struct WatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    @CloudStorage("com.clic.subscriptions") var activeSubscription: Bool = false

    @State private var router: Router = Router()
    @State private var sonosService = SonosService.shared
    @State private var popover = Popover.shared
    @State private var selected: String?

    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true

    var body: some Scene {
        WindowGroup {
            DeviceListView(activeSubscription: $activeSubscription, selected: $selected)
                .environment(router)
                .withEnvironments()
                .onChange(of: selected) {
                    print("Update current")
                    if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                        sonosService.selectedGroup = sonosService.sorted[index]
                    }
                }
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["Super"]?.lowercased() == "true" {
                        activeSubscription = true
                    }
                    #endif
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
            if autoLaunchNowPlaying {
                Task {
                    try? await sonosService.updateGroupsCheckPlayback()
                    if selected == nil {
                        let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
                        if playingGroups.count == 1, let groupPlaying = playingGroups.first {
                            Task { @MainActor in
                                selected = groupPlaying.coordinatorID
                            }
                        }
                    }
                }
            }

            if sonosService.selectedGroup != nil {
                Task {
                    try? await sonosService.fetch(useCache: true)
                }
            }
            sonosService.monitorWatch(useCache: true)
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
