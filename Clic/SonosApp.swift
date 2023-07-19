import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit

@main
struct SonosApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?

    var sonosService = SonosService()

    var body: some Scene {
        WindowGroup {
            ContentView(selected: $selected)
                .environment(sonosService)
                .task {
                    sonosService.monitor()
                }
        }.onChange(of: scenePhase) { oldValue, newValue in
            if newValue == .background {
                WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
            }
            if newValue == .active {
                Task {
                    try await Task.sleep(for: .milliseconds(300))
                    selected = sonosService.groups.first(where: { room in
                        room.coordinatorRoom.isPlaying
                    })?.coordinatorID
                }
            }
        }
        .onChange(of: sonosService.groups.map(\.coordinatorRoom.isPlaying)) {
            LiveActivityManager.shared.createActivity(with: sonosService.groups)
        }
//        .backgroundTask(.appRefresh(UUID().uuidString)) { action in
//            LiveActivityManager.shared.refresh()
//        }
    }
}
