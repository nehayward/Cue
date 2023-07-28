import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit

@main
struct SonosApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?
    @State var showPaywall: Bool = false

    @AppStorage("membership") var isEnabled = false

    var sonosService = SonosService()
    var superMember = SuperMember()

    var body: some Scene {
        WindowGroup {
            ContentView(selected: $selected)
                .environment(sonosService)
                .environment(superMember)
                .task {
                    sonosService.monitor()
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallScreen()
                        .environment(superMember)
                }
                .overlay(alignment: .bottom) {
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
        }.onChange(of: scenePhase) {
            if scenePhase == .background {
                WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
            }
            if scenePhase == .active {
                Task {
                    try await Task.sleep(for: .milliseconds(300))
                    selected = sonosService.groups.first(where: { room in
                        room.coordinatorRoom.isPlaying
                    })?.coordinatorID
                }
                superMember.isEnabled = isEnabled
            }
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            LiveActivityManager.shared.createActivity(with: sonosService.groups)
        }
        .onChange(of: superMember.isEnabled) {
            isEnabled = superMember.isEnabled
        }
//        .backgroundTask(.appRefresh(UUID().uuidString)) { action in
//            LiveActivityManager.shared.refresh()
//        }
    }
}
