import SonosKit
import SwiftUI

/// The on-device library as sections for a `List`: Play and Shuffle across
/// everything here, then Artists, Albums, Songs and Playlists, the way a
/// provider's front page reads, each filtered to what's on the device and
/// searchable without a network, the books downloaded, and a shelf of the
/// albums and playlists downloaded last. Everything, whatever the
/// provider, in the Downloads tab and for Offline Mode; narrowed to one
/// provider's songs from Settings ▸ Storage.
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
        // recounts the rows; the library itself is static. The summary,
        // not the downloads themselves, which move with every byte.
        let _ = downloads.musicSummary
        let _ = apple.version
        let _ = files.indexVersion
        let songCount = OnDeviceLibrary.allSongs(in: service).count
        // Books are the Audiobooks tab's to play; listed only with every
        // provider's songs.
        let bookCount = service == nil ? downloads.musicSummary.books : 0

        if songCount > 0 {
            playSection
        }
        if songCount > 0 || bookCount > 0 {
            librarySection(songCount: songCount, bookCount: bookCount)
        }
        if songCount > 0 {
            recentSection
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
                    // The symbol inline, as the album header has it: a
                    // `Label` in a list row drops its icon.
                    Text("\(Image(systemName: "play.fill")) Play")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await playEverything(shuffle: true) }
                } label: {
                    Text("\(Image(systemName: "shuffle")) Shuffle")
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

    /// The library over what's here: Artists, Albums, Songs, Playlists
    /// and Books, with a count on each, plus where it all came from in the
    /// footer.
    private func librarySection(songCount: Int, bookCount: Int) -> some View {
        let playlistCount = OnDeviceLibrary.groups(.playlists, sortedBy: .title, descending: false, in: service).count
        return Section {
            if songCount > 0 {
                NavigationLink(value: RouterDestination.onDeviceCollection(.artists, service: service)) {
                    libraryRow("Artists", systemImage: OnDeviceCollection.artists.systemImage, count: OnDeviceLibrary.groups(.artists, sortedBy: .title, descending: false, in: service).count)
                }
                NavigationLink(value: RouterDestination.onDeviceCollection(.albums, service: service)) {
                    libraryRow("Albums", systemImage: OnDeviceCollection.albums.systemImage, count: OnDeviceLibrary.groups(.albums, sortedBy: .title, descending: false, in: service).count)
                }
                NavigationLink(value: songsDestination) {
                    libraryRow("Songs", systemImage: "music.note", count: songCount)
                }
            }
            if playlistCount > 0 {
                NavigationLink(value: RouterDestination.onDeviceCollection(.playlists, service: service)) {
                    libraryRow("Playlists", systemImage: OnDeviceCollection.playlists.systemImage, count: playlistCount)
                }
            }
            if bookCount > 0 {
                // The books downloaded or on their way, where they're
                // looked after.
                NavigationLink(value: RouterDestination.bookDownloads) {
                    libraryRow("Books", systemImage: "book", count: bookCount)
                }
            }
        } header: {
            Text("On This Device")
        } footer: {
            if songCount > 0 {
                Text(sourcesLine)
            }
        }
    }

    /// The albums and playlists downloaded last, as covers, each opening
    /// on its page.
    @ViewBuilder
    private var recentSection: some View {
        let recent = OnDeviceLibrary.recentlyDownloaded(in: service)
        if !recent.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(recent) { group in
                            NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
                                RecentDownloadTile(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("Recently Downloaded")
            }
        }
    }

    /// A row of the library. The icon in the text's colour, not the accent:
    /// the counts are what the eye goes to.
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
                .foregroundStyle(.primary)
        }
    }

    /// Where the songs came from — the downloads, the Music app, the Files
    /// folder — so the counts above have a source.
    private var sourcesLine: String {
        let downloaded = service == nil
            ? downloads.songsHere.count
            : downloads.songsHere.filter { $0.service == service }.count
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

/// An album or playlist on the Recently Downloaded shelf: its cover, with
/// its name and the line under it.
private struct RecentDownloadTile: View {
    let group: OnDeviceLibrary.Group

    private static let size: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ContentArtworkView(content: group.container, showMusicSource: false, preferredSize: 300, cornerRadius: 6)
                .frame(width: Self.size, height: Self.size)
            Text(group.title)
                .font(.footnote)
                .lineLimit(1)
            Text(group.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: Self.size)
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
