import Foundation

extension Bundle {
    var iconFileNames: [String] {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternateIcons = icons["CFBundleAlternateIcons"] as? [String: Any] else {
            return []
        }
        var alternates = Set(alternateIcons.keys).sorted()
        alternates.removeAll { key in
            key == "Default"
        }
        alternates.insert("Default", at: 0)
        return Array(alternates)
    }
}
