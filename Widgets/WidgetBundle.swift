import WidgetKit
import SwiftUI

@main
struct SonosWidgetBundle: WidgetBundle {
    var body: some Widget {
        // NOTE: workaround WidgetBundleBuilder bug
        if #available(iOS 18.0, *) {
            return body_iOS18
        } else {
            return body_iOS17
        }
    }
}

@WidgetBundleBuilder
private var body_iOS17: some Widget {
    RemoteWidget()
    #if canImport(ActivityKit)
    LiveActivityNowPlayingWidget()
    #endif
}

@available(iOS 18.0, *)
@WidgetBundleBuilder
private var body_iOS18: some Widget {
    RemoteWidget()
    #if canImport(ActivityKit)
    LiveActivityNowPlayingWidget()
    #endif
    RemoteControlWidget()
    LaunchAppControlWidget()
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

@available(iOS, deprecated: 18.0, message: "use WidgetAccentedRenderingMode instead")
enum BackdeployedWidgetAccentedRenderingMode {
    case accented
    case accentedDesaturated
    case desaturated
    case fullColor
    
    @available(iOS 18.0, *)
    func toRenderingMode() -> WidgetAccentedRenderingMode {
        switch self {
        case .accented: .accented
        case .accentedDesaturated: .accentedDesaturated
        case .desaturated: .desaturated
        case .fullColor: .fullColor
        }
    }
}

extension Image {
    @available(iOS, deprecated: 18.0, message: "use widgetAccentedRenderingMode instead")
    @ViewBuilder
    func backdeployedWidgetAccentedRenderingMode(
        _ mode: BackdeployedWidgetAccentedRenderingMode
    ) -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(mode.toRenderingMode())
        }
        else {
            self
        }
    }
}
