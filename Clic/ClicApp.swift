import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit
import CloudStorage

@main
struct ClicApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State private var selected: String?
    @State private var showPaywall: Bool = false
    @State private var liveActivityManager: LiveActivityManager? = nil

    @CloudStorage("sonos_ip") var ip: String?
    private var sonosService = SonosService()
    private var alertService = AlertService()
    private var superMember = SubscriptionService()

    var body: some Scene {
        WindowGroup {
            DeviceListView(selected: $selected)
                .environment(sonosService)
                .environment(superMember)
                .environment(alertService)
                .overlay(alignment: .top) {
                    Text("\(ip ?? "")")
                        .fontDesign(.rounded)
                        .fontWidth(.compressed)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor.gradient)
                        .padding()
                        .background(.thickMaterial)
                        .clipShape(Capsule())
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallScreen()
                        .environment(superMember)
                }
                .safeAreaInset(edge: .bottom) {
                    if !superMember.isEnabled {
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Show all devices (\(sonosService.groups.count))")
                                .fontDesign(.rounded)
                                .fontWidth(.compressed)
                                .foregroundStyle(Color.accentColor.gradient)
                                .padding()
                                .background(.thickMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
                .onAppear {
                    liveActivityManager = LiveActivityManager(sonosService: sonosService)
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            liveActivityManager?.createActivity(with: sonosService.groups)
        }
        .onChange(of: superMember.isEnabled) {
            //            isEnabled = superMember.isEnabled
        }
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitor()

            // MARK: Add back when monitoring is fixed
            Task {
                try? await sonosService.updateGroupsCheckPlayback()

                if selected == nil {
                    let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
                    if playingGroups.count == 1, let groupPlaying = playingGroups.first {
                        try await Task.sleep(for: .milliseconds(200))
                        alertService.showAlert(with: "Jumped to \(groupPlaying.coordinatorRoom.name)")
                        selected = groupPlaying.coordinatorID
                    }
                }
            }
        case .inactive:
            print("Inactive")
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
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
