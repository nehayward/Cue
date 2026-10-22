import SwiftUI
import WatchSync

/// The watch's settings, top left on the home screen: the quality songs
/// come down at, the room they and the books take (and taking them all
/// off), which sign-ins the iPhone has shared, and the version and build.
struct SettingsScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchAccounts.self) private var accounts
    @State private var isChoosingQuality = false
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        List {
            Section {
                Button {
                    isChoosingQuality = true
                } label: {
                    LabeledContent("Quality", value: store.quality.title)
                }
            } footer: {
                Text("\(store.quality.detail). Books come down as your server keeps them.")
            }

            Section {
                LabeledContent("Songs", value: "\(store.downloadedCount)")
                if !store.books.isEmpty {
                    LabeledContent("Books", value: "\(store.downloadedBookCount)")
                }
                LabeledContent("Space Used", value: ByteCountFormatter.string(fromByteCount: store.bytesUsed, countStyle: .file))
                if !store.picks.items.isEmpty {
                    Button(role: .destructive) {
                        isConfirmingRemoveAll = true
                    } label: {
                        Text("Remove All Downloads")
                    }
                }
            } header: {
                Text("Storage")
            }

            Section {
                LabeledContent("Plex", value: accounts.hasPlex ? "Signed In" : "Off")
                LabeledContent("Subsonic", value: accounts.hasSubsonic ? "Signed In" : "Off")
                LabeledContent("Audiobookshelf", value: accounts.hasAudiobookshelf ? "Signed In" : "Off")
            } header: {
                Text("Accounts")
            } footer: {
                Text("Sign in on your iPhone, then open Cue there once to bring the sign-ins here.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isChoosingQuality) {
            QualityPicker(current: store.quality) { quality in
                isChoosingQuality = false
                store.setQuality(quality)
            }
        }
        .confirmationDialog("Remove All Downloads?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) {
                store.removeAll()
            }
        } message: {
            Text("They come off this watch and your iPhone's list. They stay on your server.")
        }
    }

    /// The version and build, as "2026.8 (674)".
    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()
}

/// Which quality songs come down at — asked the first time there's music
/// to fetch, and changed in Settings.
struct QualityPicker: View {
    var current: WatchDownloadQuality?
    let choose: (WatchDownloadQuality) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WatchDownloadQuality.allCases) { quality in
                        Button {
                            choose(quality)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(quality == .recommended ? "\(quality.title) (Recommended)" : quality.title)
                                    Text(quality.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if quality == current {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Your watch has much less room than your iPhone, so songs can be converted to MP3 as they download. Changing it converts the songs already here.")
                }
            }
            .navigationTitle("Quality")
        }
    }
}
