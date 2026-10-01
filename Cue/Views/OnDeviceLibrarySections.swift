import SonosKit
import SwiftUI

/// The on-device library as sections for a `List`: Play and Shuffle across
/// everything here, then Artists, Albums and Songs, the way a provider's
/// front page reads, each filtered to what's on the device and searchable
/// without a network. Narrowed to one provider's songs on its Downloaded
/// page; everything, whatever the provider, for Offline Mode.
///
/// Shows nothing when the library is empty — the screen around it says
/// what to download.
struct OnDeviceLibrarySections: View {
    /// The provider to show, or nil for all of them.
    var service: MusicService? = nil

    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        // Read here so a download finishing or an index rebuilding
        // recounts the rows; the library itself is static.
        let _ = downloads.completed.count
        let _ = apple.version
        let _ = files.indexVersion
        let songCount = OnDeviceLibrary.allSongs(in: service).count

        if songCount > 0 {
            playSection
            librarySection(songCount: songCount)
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
    private func librarySection(songCount: Int) -> some View {
        Section {
            NavigationLink(value: RouterDestination.onDeviceCollection(.artists, service: service)) {
                libraryRow("Artists", systemImage: OnDeviceCollection.artists.systemImage, count: OnDeviceLibrary.groups(.artists, sortedBy: .title, descending: false, in: service).count)
            }
            NavigationLink(value: RouterDestination.onDeviceCollection(.albums, service: service)) {
                libraryRow("Albums", systemImage: OnDeviceCollection.albums.systemImage, count: OnDeviceLibrary.groups(.albums, sortedBy: .title, descending: false, in: service).count)
            }
            NavigationLink(value: songsDestination) {
                libraryRow("Songs", systemImage: "music.note", count: songCount)
            }
        } header: {
            Text("On This Device")
        } footer: {
            Text(sourcesLine)
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

    /// Where the songs came from — the downloads, the Music app, the Files
    /// folder — so the counts above have a source.
    private var sourcesLine: String {
        let downloaded = service == nil
            ? downloads.completed.count
            : downloads.completed.filter { $0.service == service }.count
        let appleCount = service == nil || service == .apple ? OnDeviceLibrary.appleSongs.count : 0
        let fileCount = service == nil || service == .files ? OnDeviceLibrary.fileSongs.count : 0

        var parts: [String] = []
        if downloaded > 0 {
            parts.append(downloaded == 1 ? "1 downloaded song" : "\(downloaded.formatted()) downloaded songs")
        }
        if appleCount > 0 {
            parts.append("\(appleCount == 1 ? "1 song" : "\(appleCount.formatted()) songs") downloaded in the Music app")
        }
        if fileCount > 0 {
            parts.append("\(fileCount == 1 ? "1 song" : "\(fileCount.formatted()) songs") from \(files.folderName ?? "your Files folder")")
        }
        return parts.formatted(.list(type: .and, width: .standard)) + ". Search any list to find a song without a network."
    }

    /// Every song here: sorted and searched on the device, with a Play All
    /// over the lot.
    private var songsDestination: RouterDestination {
        let service = service
        return .playableList(
            title: "Songs",
            playAllItem: OnDeviceLibrary.allSongsContainer(in: service),
            showSectionIndex: false,
            sortOptions: OnDeviceLibrary.SongSort.allCases.map { sort in
                PlayableListSort(
                    name: sort.label,
                    ascendingLabel: sort.ascendingLabel,
                    descendingLabel: sort.descendingLabel,
                    defaultsToDescending: sort.prefersDescending
                ) { offset, descending in
                    offset == 0 ? OnDeviceLibrary.songs(sortedBy: sort, descending: descending, in: service) : []
                }
            },
            sortKey: "onDevice.songs.\(service?.sonosRawValue ?? "all")",
            searchAction: { query, offset in
                offset == 0 ? OnDeviceLibrary.searchSongs(query, in: service) : []
            },
            loadingStatus: {
                let count = OnDeviceLibrary.allSongs(in: service).count
                return count == 0 ? nil : (count == 1 ? "1 song" : "\(count.formatted()) songs")
            },
            changeToken: { OnDeviceLibrary.changeToken }
        )
    }

    /// Everything here into the local queue. Through the router rather
    /// than the player directly: it announces, records the play, and —
    /// offline — already sends everything to this device.
    private func playEverything(shuffle: Bool) async {
        // Shuffled here: the local queue's own shuffle only reorders the
        // pages of a container, and these are plain songs.
        let all = OnDeviceLibrary.allSongs(in: service)
        let songs = shuffle ? all.shuffled() : all
        guard !songs.isEmpty else { return }
        await PlayDestinationRouter.play(songs, position: .replace) { group, position in
            try await SonosService.shared.queue(contents: songs, group: group, position: position, startIndex: 0)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            OnDeviceLibrarySections(service: .apple)
        }
    }
    .withEnvironments()
}
