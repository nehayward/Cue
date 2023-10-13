import Foundation

extension Bundle {
    var iconFileNames: [String] {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternateIcons = icons["CFBundleAlternateIcons"] as? [String: Any] else {
            return []
        }
        var alternates = Array(alternateIcons.keys).sorted()
        alternates.insert("Default", at: 0)
        return alternates
    }
}
