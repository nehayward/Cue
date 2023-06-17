import SwiftUI
import SonosKit

@main
struct SonosApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                MusicSearchScreen()
            }
        }
    }
}
