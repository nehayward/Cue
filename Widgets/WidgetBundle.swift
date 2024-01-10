import WidgetKit
import SwiftUI

@main
struct SonosWidgetBundle: WidgetBundle {
    var body: some Widget {
        RemoteWidget()
        #if canImport(ActivityKit)
        LiveActivityNowPlayingWidget()
        #endif
    }
}
