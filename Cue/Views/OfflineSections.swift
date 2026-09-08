import MusicSearchKit
import SonosKit
import SwiftUI

/// What the home screen shows while `OfflineMode` is active, as sections
/// for a `List`: why the providers aren't there, and what's on this
/// device — the downloads and the Files folder's local songs, each a row
/// into its list, with Play and Shuffle across the lot. Home hosts these
/// on iPad and Mac; on the phone, whose home is Browse,
/// `OfflineBrowseScreen` does.
struct OfflineSections: View {
    @State private var offline = OfflineMode.shared
    @State private var downloads = DownloadManager.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        offlineSection
        onThisDeviceSection
    }

    /// Why the providers aren't showing: the network is gone, or the user
    /// asked. The switch is the one thing worth offering here — with no
    /// network there's nothing to turn off.
    private var offlineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(offline.hasNetwork ? "Offline Mode" : "You're Offline")
                        .font(.headline)
                } icon: {
                    Image(systemName: offline.hasNetwork ? "airplane" : "wifi.slash")
                        .foregroundStyle(.secondary)
                }
                Text(offline.hasNetwork
                     ? "Showing only what's on this device. Everything plays here rather than on a speaker."
                     : "No connection, so this is what's on this device. It plays here; your speakers are back when the network is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if offline.isOn {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        withAnimation(.spring(response: 0.3)) {
                            offline.isOn = false
                        }
                    } label: {
                        Text("Turn Off Offline Mode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Empty, it says what to download next time.
    private var onThisDeviceSection: some View {
        let downloaded = downloads.completed
        let fileSongs = OnDeviceLibrary.fileSongs

        return Section {
            if downloaded.isEmpty, fileSongs.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on This Device", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download Plex or Subsonic songs from their menus, or keep a Files folder on this device, and they'll be here when you're offline.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !downloaded.isEmpty {
                    NavigationLink(value: RouterDestination.playableList(
                        title: "Downloads",
                        showSectionIndex: false,
                        changeToken: { downloads.completed.count },
                        action: { offset in offset == 0 ? OnDeviceLibrary.downloadedSongs : [] }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Downloads")
                                Text(downloadsSubtitle(downloaded))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                    }
                }

                if !fileSongs.isEmpty {
                    NavigationLink(value: RouterDestination.playableList(
                        title: files.folderName ?? "Files",
                        showSectionIndex: false,
                        changeToken: { files.indexVersion },
                        action: { offset in offset == 0 ? OnDeviceLibrary.fileSongs : [] }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(files.folderName ?? "Files")
                                Text(fileSongs.count == 1
                                     ? "1 song on this device"
                                     : "\(fileSongs.count.formatted()) songs on this device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            MediaSearchService.files.iconForMusicService
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
        } header: {
            Text("On This Device")
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

    private func downloadsSubtitle(_ downloaded: [DownloadManager.Item]) -> String {
        let count = downloaded.count == 1 ? "1 song" : "\(downloaded.count.formatted()) songs"
        let services = Set(downloaded.map(\.service.title))
            .sorted()
            .formatted(.list(type: .and, width: .narrow))
        return services.isEmpty ? count : "\(count) • \(services)"
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
