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
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task {
                    do {
                        try await sonosService.updateGroupsCheckPlayback()
                        print("Tock", Date.now)
                    } catch {
                        print(error)
                        // Restart Search
                        sonosService.monitorWatch()
                    }
                    if selected == nil {
                        selected = sonosService.groups.first(where: { room in
                            room.coordinatorRoom.isPlaying
                        })?.coordinatorID
                    }
                    sonosService.monitorWatch()
                }
            case .inactive:
                sonosService.systemNotFound = false
                Task {
                    sonosService.sonosPulse.cancel()
                }
            case .background:
                sonosService.systemNotFound = false
                break
            @unknown default:
                break
            }
        }
    }
}
