import SwiftUI
import SonosKit

@main
struct SonosWatchApp: App {
    var sonosService = SonosService()
    var popOver = Popover()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(popOver)
                .environment(sonosService)
                .task {
                    sonosService.monitor()
                }
        }
    }
}
