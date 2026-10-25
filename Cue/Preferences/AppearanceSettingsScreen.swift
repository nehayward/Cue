import Defaults
import SwiftUI

/// Settings ▸ Appearance: the theme, and which optional tabs show.
struct AppearanceSettingsScreen: View {
    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(AppStorageKeys.showRadioTab) private var showRadioTab: Bool = true
    @AppStorage(AppStorageKeys.showAudiobooksTab) private var showAudiobooksTab: Bool = true

    var body: some View {
        Form {
            Section {
                Label {
                    Picker("Theme", selection: $colorScheme) {
                        ForEach(ColorSchemePreference.allCases, id: \.hashValue) { scheme in
                            Text(scheme.rawValue.capitalized)
                                .tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                } icon: {
                    SettingsIcon(symbol: "circle.lefthalf.filled", colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)])
                }
            }

            Section {
                Label {
                    Toggle(isOn: $showRadioTab) {
                        SettingsRowText(title: "Show Radio Tab", detail: "TuneIn and Apple Music stations in a tab of their own. Hidden on its own while offline.")
                    }
                    .tint(.accent)
                } icon: {
                    SettingsIcon(symbol: "radio", colors: [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 0.8, green: 0.2, blue: 0.35)])
                }
                Label {
                    Toggle(isOn: $showAudiobooksTab) {
                        SettingsRowText(title: "Show Audiobooks Tab", detail: "The book you're listening to, ready to resume, and every book on Plex and Audiobookshelf. Hidden on its own while offline.")
                    }
                    .tint(.accent)
                } icon: {
                    SettingsIcon(symbol: "book.fill", colors: [Color(red: 0.98, green: 0.6, blue: 0.2), Color(red: 0.9, green: 0.42, blue: 0.1)])
                }
            } header: {
                Text("Tabs")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}
