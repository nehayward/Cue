import SwiftUI
import SonosKit
import ActivityKit
import WidgetKit

@Observable
class Popover {
    var isShowing: Bool = false
    var text: String = ""
}

@main
struct SonosApp: App {
    @Environment(\.scenePhase) var scenePhase

    var sonosService = SonosService()
    @State var popOver = Popover()

    var body: some Scene {
        WindowGroup {
            NavigationStack{
                ContentView()
            }
            .environment(sonosService)
            .environment(popOver)
            .task {
                sonosService.monitor()
                LiveActivityManager.shared.createActivity()
            }
            .sheet(isPresented: $popOver.isShowing) {
                Text("Group")
            }
        }.onChange(of: scenePhase) { oldValue, newValue in
            if newValue == .background {
                WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
            }
        }
    }
}



