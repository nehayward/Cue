import MusicSearchKit
import SonosKit
import SwiftUI

/// What the home screen shows while `OfflineMode` is active, as sections
/// for a `List`: one line on why the providers aren't there, Play and
/// Shuffle across everything on this device, and then the on-device
/// library — Artists, Albums and Songs, the way a provider's front page
/// reads, each filtered to what's here and searchable without a network.
/// Home hosts these on iPad and Mac; on the phone, whose home is Browse,
/// `OfflineBrowseScreen` does.
struct OfflineSections: View {
    @State private var offline = OfflineMode.shared
    @State private var downloads = DownloadManager.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        // Read here so a download finishing or the Files index rebuilding
        // recounts the rows; the library itself is static.
        let downloadedCount = downloads.completed.count
        let fileSongs = OnDeviceLibrary.fileSongs

        statusSection
        if downloadedCount == 0, fileSongs.isEmpty {
            emptySection
        } else {
            playSection
            librarySection(songCount: downloadedCount + fileSongs.count, downloadedCount: downloadedCount, fileCount: fileSongs.count)
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

    /// The library over what's here: Artists, Albums and Songs, with a
    /// count on each, plus where it all came from in the footer.
    private func librarySection(songCount: Int, downloadedCount: Int, fileCount: Int) -> some View {
        Section {
            NavigationLink(value: RouterDestination.onDeviceCollection(.artists)) {
                libraryRow("Artists", systemImage: OnDeviceCollection.artists.systemImage, count: OnDeviceLibrary.artists.count)
            }
            NavigationLink(value: RouterDestination.onDeviceCollection(.albums)) {
                libraryRow("Albums", systemImage: OnDeviceCollection.albums.systemImage, count: OnDeviceLibrary.albums.count)
            }
            NavigationLink(value: songsDestination) {
                libraryRow("Songs", systemImage: "music.note", count: songCount)
            }
        } header: {
            Text("On This Device")
        } footer: {
            Text(sourcesLine(downloadedCount: downloadedCount, fileCount: fileCount))
        }
    }

    private func libraryRow(_ title: String, systemImage: String, count: Int) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(count.formatted())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    /// Where the songs came from — the downloads, the Files folder, or
    /// both — so the counts above have a source.
    private func sourcesLine(downloadedCount: Int, fileCount: Int) -> String {
        var parts: [String] = []
        if downloadedCount > 0 {
            parts.append(downloadedCount == 1 ? "1 downloaded song" : "\(downloadedCount.formatted()) downloaded songs")
        }
        if fileCount > 0 {
            parts.append("\(fileCount == 1 ? "1 song" : "\(fileCount.formatted()) songs") from \(files.folderName ?? "your Files folder")")
        }
        return parts.joined(separator: " and ") + ". Search any list to find a song without a network."
    }

    /// Every song here: sorted and searched on the device, with a Play All
    /// over the lot.
    private var songsDestination: RouterDestination {
        .playableList(
            title: "Songs",
            playAllItem: OnDeviceLibrary.allSongsContainer,
            showSectionIndex: false,
            sortOptions: OnDeviceLibrary.SongSort.allCases.map { sort in
                PlayableListSort(
                    name: sort.label,
                    ascendingLabel: sort.ascendingLabel,
                    descendingLabel: sort.descendingLabel,
                    defaultsToDescending: sort.prefersDescending
                ) { offset, descending in
                    offset == 0 ? OnDeviceLibrary.songs(sortedBy: sort, descending: descending) : []
                }
            },
            sortKey: "onDevice.songs",
            searchAction: { query, offset in
                offset == 0 ? OnDeviceLibrary.searchSongs(query) : []
            },
            loadingStatus: {
                let count = OnDeviceLibrary.allSongs.count
                return count == 0 ? nil : (count == 1 ? "1 song" : "\(count.formatted()) songs")
            },
            changeToken: { OnDeviceLibrary.changeToken }
        )
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
