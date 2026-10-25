import Defaults
import SwiftUI

/// Settings ▸ Appearance: the theme, picked from three small screens drawn
/// in it as the iPhone's Display & Brightness does, and which optional tabs
/// show.
struct AppearanceSettingsScreen: View {
    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(AppStorageKeys.showRadioTab) private var showRadioTab: Bool = true
    @AppStorage(AppStorageKeys.showAudiobooksTab) private var showAudiobooksTab: Bool = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    ForEach(ColorSchemePreference.allCases, id: \.self) { option in
                        ThemeChoice(option: option, isSelected: colorScheme == option) {
                            HapticManager.shared.fireHaptic(.selection)
                            colorScheme = option
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Theme")
            }

            Section {
                Toggle(isOn: $showRadioTab) {
                    Label {
                        Text("Radio")
                    } icon: {
                        SettingsIcon(symbol: "radio", colors: [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 0.8, green: 0.2, blue: 0.35)])
                    }
                }
                .tint(.accent)
                Toggle(isOn: $showAudiobooksTab) {
                    Label {
                        Text("Audiobooks")
                    } icon: {
                        SettingsIcon(symbol: "book.fill", colors: [Color(red: 0.98, green: 0.6, blue: 0.2), Color(red: 0.9, green: 0.42, blue: 0.1)])
                    }
                }
                .tint(.accent)
            } header: {
                Text("Tabs")
            } footer: {
                Text("Both hide on their own while you're offline.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}

/// One theme: a small screen drawn in it, its name, and a selection circle.
/// No animated symbol swap, which costs the Mac a burst of GPU memory.
private struct ThemeChoice: View {
    let option: ColorSchemePreference
    let isSelected: Bool
    let select: () -> Void

    private var title: String { option.rawValue.capitalized }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                ThemePreview(option: option)
                    .frame(width: 60, height: 104)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accent : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                    }
                Text(title)
                    .font(.subheadline)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accent : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        // Three buttons in one row: without a style of its own, a tap on
        // the row would press all of them.
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A tiny screen in the theme: light, dark, or for System half of each.
private struct ThemePreview: View {
    let option: ColorSchemePreference

    var body: some View {
        switch option {
        case .light:
            MiniScreen(isDark: false)
        case .dark:
            MiniScreen(isDark: true)
        case .system:
            MiniScreen(isDark: false)
                .overlay {
                    MiniScreen(isDark: true)
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear
                                Color.black
                            }
                        }
                }
        }
    }
}

/// Artwork, a title and a subtitle, and a tab bar, in a theme's colours.
private struct MiniScreen: View {
    let isDark: Bool

    var body: some View {
        let ink = isDark ? Color.white : Color.black
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isDark ? Color(white: 0.1) : Color(white: 0.97))
            .overlay {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accent.gradient)
                        .aspectRatio(1, contentMode: .fit)
                    Capsule()
                        .fill(ink.opacity(0.8))
                        .frame(height: 4)
                    Capsule()
                        .fill(ink.opacity(0.35))
                        .frame(width: 24, height: 4)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(ink.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}
