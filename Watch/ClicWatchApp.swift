import SwiftUI
import SonosKit
import WidgetKit

@main
struct ClicWatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?

    var sonosService = SonosService()
    var popOver = Popover()

    var body: some Scene {
        WindowGroup {
            ContentView(selected: $selected)
                .environment(popOver)
                .environment(sonosService)
                .task {
                    sonosService.monitorWatch()
                }
        }.onChange(of: scenePhase) { oldValue, newValue in
            if newValue == .active {
                Task {
                    try await Task.sleep(for: .seconds(1))
                    selected = sonosService.groups.first(where: { room in
                        room.coordinatorRoom.isPlaying
                    })?.coordinatorID
                }
            }
            if newValue == .background {
                WidgetCenter.shared.reloadTimelines(ofKind: "WatchWidget")
            }
        }
    }
}
