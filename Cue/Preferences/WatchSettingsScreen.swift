import NukeUI
import SwiftUI
import WatchSync

/// What's set to go on the Apple Watch — the albums, playlists, artists and
/// songs added here or on the watch — and how to make the watch download
/// faster. The watch does the downloading and owns the quality. Reached
/// from Settings › Storage when a watch is paired.
struct WatchSettingsScreen: View {
    @State private var watch = WatchSyncService.shared
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        List {
            if !watch.isWatchAppInstalled {
                Section {
                    ContentUnavailableView(
                        "Cue Isn't on Your Watch",
                        systemImage: "applewatch",
                        description: Text("Open the Watch app on this iPhone and install Cue under Available Apps.")
                    )
                }
            } else if watch.picks.items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing on Your Watch",
                        systemImage: "applewatch",
                        description: Text("Choose Add to Apple Watch from a Plex or Subsonic album, playlist or song's menu, or browse your library in Cue on your watch.")
                    )
                }
            } else {
                Section {
                    ForEach(watch.picks.items, id: \.key) { pick in
                        row(pick)
                            .swipeActions {
                                Button(role: .destructive) {
                                    watch.remove(key: pick.key)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("On Apple Watch")
                } footer: {
                    Text("Your watch downloads these from your server by itself, at the quality set on the watch. Swipe to remove.")
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingRemoveAll = true
                    } label: {
                        Label("Remove All from Apple Watch", systemImage: "trash")
                    }
                }
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fast Download")
                        Text("Open Cue on your watch and tap Fast Download, then turn off Bluetooth on this iPhone in Settings › Bluetooth.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundStyle(.tint)
                }
            } footer: {
                Text("While your iPhone is connected over Bluetooth, your watch downloads through it. With Bluetooth off, the watch uses its own Wi‑Fi and is many times faster. Control Center's Bluetooth button leaves your watch connected, so use Settings. Headphones stay connected to your watch.")
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove everything from Apple Watch?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) {
                watch.removeAll()
            }
        } message: {
            Text("The songs are deleted from your watch. They stay on your server and can be added again.")
        }
    }

    private func row(_ pick: WatchPick) -> some View {
        HStack(spacing: 12) {
            LazyImage(url: pick.artworkURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(pick.title)
                    .lineLimit(1)
                Text([kindTitle(pick.kind), pick.subtitle].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func kindTitle(_ kind: WatchPick.Kind) -> String {
        switch kind {
        case .album: "Album"
        case .playlist: "Playlist"
        case .artist: "Artist"
        case .song: "Song"
        }
    }
}
