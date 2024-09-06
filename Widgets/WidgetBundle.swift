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
            LaunchAppControlWidget()
        }
    }
}

// MARK: iOS 18 Remove if iOS 18
extension WidgetConfiguration {
    func promptsForUserConfigurationIfiOS18() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 18.0, *) {
            return promptsForUserConfiguration()
        } else {
            return self
        }
    }
}
