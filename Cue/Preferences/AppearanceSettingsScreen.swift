import Defaults
import SwiftUI

/// Settings ▸ Appearance: the theme, picked from three swatches (light,
/// dark, and half of each for System), and which optional tabs show.
struct AppearanceSettingsScreen: View {
    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(AppStorageKeys.showRadioTab) private var showRadioTab: Bool = true
    @AppStorage(AppStorageKeys.showAudiobooksTab) private var showAudiobooksTab: Bool = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 32) {
                    ForEach(ColorSchemePreference.allCases, id: \.self) { option in
                        ThemeChoice(option: option, isSelected: colorScheme == option) {
                            HapticManager.shared.fireHaptic(.selection)
                            colorScheme = option
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
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

/// One theme: its swatch, ringed in the accent while chosen, over its name.
private struct ThemeChoice: View {
    let option: ColorSchemePreference
    let isSelected: Bool
    let select: () -> Void

    private var title: String { option.rawValue.capitalized }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                ThemeSwatch(option: option)
                    .frame(width: 40, height: 40)
                    .padding(4)
                    .overlay {
                        Circle()
                            .strokeBorder(isSelected ? Color.accent : .clear, lineWidth: 2.5)
                    }
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        // Three buttons in one row: without a style of its own, a tap on
        // the row would press all of them.
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A circle in the theme: white, black, or for System half of each.
private struct ThemeSwatch: View {
    let option: ColorSchemePreference

    var body: some View {
        Circle()
            .fill(option == .dark ? Color.black : Color.white)
            .overlay {
                if option == .system {
                    Circle()
                        .fill(Color.black)
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear
                                Color.black
                            }
                        }
                }
            }
            // A hairline, so white shows on a light page and black on a dark one.
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
