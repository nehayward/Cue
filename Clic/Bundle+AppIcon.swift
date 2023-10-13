import Foundation

extension Bundle {
    var iconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }

    var iconFileNames: [String] {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternateIcons = icons["CFBundleAlternateIcons"] as? [String: Any] else {
            return []
        }
        print(alternateIcons)
        return Array(alternateIcons.keys)
    }
}
