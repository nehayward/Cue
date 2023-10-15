import Foundation

extension Bundle {
    var iconFileNames: [String] {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternateIcons = icons["CFBundleAlternateIcons"] as? [String: Any] else {
            return []
        }
        return Array(alternateIcons.keys).sorted()
    }
}
