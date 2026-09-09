import MusicSearchKit
import SonosKit
import SwiftUI

/// What the home screen shows while `OfflineMode` is active, as sections
/// for a `List`: one line on why the providers aren't there, Play and
/// Shuffle across everything on this device, and then the songs
/// themselves — the downloads, and the Files folder's local songs —
/// right here rather than behind a row each. Home hosts these on iPad
/// and Mac; on the phone, whose home is Browse, `OfflineBrowseScreen`
/// does.
struct OfflineSections: View {
    @State private var offline = OfflineMode.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        let downloaded = OnDeviceLibrary.downloadedSongs
        let fileSongs = OnDeviceLibrary.fileSongs

        statusSection
        if downloaded.isEmpty, fileSongs.isEmpty {
            emptySection
        } else {
            playSection
            if !downloaded.isEmpty {
                songsSection(title: "Downloads", songs: downloaded)
            }
            if !fileSongs.isEmpty {
                songsSection(title: files.folderName ?? "Files", songs: fileSongs)
            }
        }
    }

    /// Why the providers aren't showing, in a line: the network is gone,
    /// or the user asked. The switch is the one thing worth offering here,
    /// and it sits on the trailing side rather than taking a row of its own.
    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: offline.hasNetwork ? "airplane" : "wifi.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offline.hasNetwork ? "Offline Mode" : "No Connection")
                        .font(.headline)
                    Text(offline.hasNetwork
                         ? "Plays on this device"
                         : "Plays on this device until the network is back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if offline.isOn {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        withAnimation(.spring(response: 0.3)) {
                            offline.isOn = false
                        }
                    } label: {
                        Text("Turn Off")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Empty, it says what to download next time.
    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("Nothing on This Device", systemImage: "arrow.down.circle")
            } description: {
                Text("Download Plex or Subsonic songs from their menus, or keep a Files folder on this device, and they'll be here when you're offline.")
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Play and Shuffle across everything below, on their own so they sit
    /// above the first list of songs rather than inside it.
    private var playSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await playEverything(shuffle: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await playEverything(shuffle: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The songs themselves, with the count in the header: a row into a
    /// list was one tap between the user and the only music there is.
    private func songsSection(title: String, songs: [PlayableContent]) -> some View {
        Section {
            ForEach(songs) { song in
                PlayableContentView(item: song, hideContentType: true)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(songs.count == 1 ? "1 song" : "\(songs.count.formatted()) songs")
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Everything on the device into the local queue. Through the router
    /// rather than the player directly: it announces, records the play,
    /// and — offline — already sends everything to this device.
    private func playEverything(shuffle: Bool) async {
        // Shuffled here: the local queue's own shuffle only reorders the
        // pages of a container, and these are plain songs.
        let songs = shuffle ? OnDeviceLibrary.allSongs.shuffled() : OnDeviceLibrary.allSongs
        guard !songs.isEmpty else { return }
        await PlayDestinationRouter.play(songs, position: .replace) { group, position in
            try await SonosService.shared.queue(contents: songs, group: group, position: position, startIndex: 0)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            OfflineSections()
        }
    }
    .withEnvironments()
}
