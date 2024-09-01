import WidgetKit
import SwiftUI

@main
struct SonosWidgetBundle: WidgetBundle {
    var body: some Widget {
        RemoteWidget()
        #if canImport(ActivityKit)
        LiveActivityNowPlayingWidget()
        #endif
        if #available(iOSApplicationExtension 18.0, *) {
            RemoteControlWidget()
        }
    }
}
