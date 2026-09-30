import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

enum ColorSchemePreference: String, Hashable, Codable, CaseIterable {
    case system
    case light
    case dark
    
    var scheme: ColorScheme? {
        switch self {
        case .light:
                .light
        case .dark:
                .dark
        default:
            nil
        }
    }

#if canImport(UIKit) && !os(watchOS)
    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Sets the appearance on every window the app has. Set on the window
    /// rather than with `preferredColorScheme`, so it reaches sheets, full
    /// screen covers and alerts too, and System hands the choice back to
    /// the device instead of keeping the last forced one.
    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
#endif
}
