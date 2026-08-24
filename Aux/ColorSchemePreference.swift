import SwiftUI

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
}
