import Nuke
import NukeUI
import SonosKit
import SwiftUI

/// The on-device library as sections for a `List`: Play and Shuffle across
/// everything here, the albums that came down last as a shelf of covers,
/// then Artists, Albums and Songs, the way a provider's front page reads,
/// each filtered to what's on the device and searchable without a network.
/// Narrowed to one provider's songs on its Downloaded page; everything,
/// whatever the provider, for Offline Mode.
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
            // Grouped once: the shelf takes the newest, the Albums row
            // counts them all.
            let albums = OnDeviceLibrary.groups(.albums, sortedBy: .added, descending: true, in: service)
            playSection
            // Only what knows when it arrived: a Files folder's songs
            // don't, and a shelf of them in no order isn't "recent".
            let recent = albums.filter { $0.latestAdded > .distantPast }.prefix(Self.recentLimit)
            if !recent.isEmpty {
                recentSection(Array(recent))
            }
            librarySection(songCount: songCount, albumCount: albums.count)
        }
    }

    /// How many covers the shelf holds; the Albums row has the rest.
    private static let recentLimit = 12

    /// Play and Shuffle across everything below, on their own so they sit
    /// above the first list of songs rather than inside it.
    private var playSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await play(OnDeviceLibrary.allSongs(in: service), shuffle: false) }
                } label: {
                    // The symbol inline, as the album header has it: a
                    // `Label` in a list row drops its icon.
                    Text("\(Image(systemName: "play.fill")) Play")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await play(OnDeviceLibrary.allSongs(in: service), shuffle: true) }
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

    /// The albums that came down last, newest first, as covers: what was
    /// just downloaded is what's most likely wanted next. A cover opens the
    /// album's songs that are here; pressing one plays or shuffles them.
    private func recentSection(_ albums: [OnDeviceLibrary.Group]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                // A title in the row rather than a section header, so it
                // lines up with the covers and the buttons above.
                Text("Recently Downloaded")
                    .font(.title3.weight(.semibold))
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            NavigationLink(value: OnDeviceLibrary.destination(for: album)) {
                                OnDeviceAlbumTile(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task { await play(album.tracks, shuffle: false) }
                                } label: {
                                    Label("Play", systemImage: "play")
                                }
                                Button {
                                    Task { await play(album.tracks, shuffle: true) }
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The library over what's here: Artists, Albums and Songs, with a
    /// count on each, plus where it all came from in the footer. No header:
    /// the page is the device's, so "on this device" goes without saying.
    private func librarySection(songCount: Int, albumCount: Int) -> some View {
        Section {
            NavigationLink(value: RouterDestination.onDeviceCollection(.artists, service: service)) {
                libraryRow("Artists", systemImage: OnDeviceCollection.artists.systemImage, count: OnDeviceLibrary.groups(.artists, sortedBy: .title, descending: false, in: service).count)
            }
            NavigationLink(value: RouterDestination.onDeviceCollection(.albums, service: service)) {
                libraryRow("Albums", systemImage: OnDeviceCollection.albums.systemImage, count: albumCount)
            }
            NavigationLink(value: songsDestination) {
                libraryRow("Songs", systemImage: "music.note", count: songCount)
            }
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

    /// Songs from here — everything, or one album's — into the queue.
    /// Through the router rather than the player directly: it announces,
    /// records the play, and — offline — already sends everything to this
    /// device.
    private func play(_ songs: [PlayableContent], shuffle: Bool) async {
        // Shuffled here: the local queue's own shuffle only reorders the
        // pages of a container, and these are plain songs.
        let songs = shuffle ? songs.shuffled() : songs
        guard !songs.isEmpty else { return }
        await PlayDestinationRouter.play(songs, position: .replace) { group, position in
            try await SonosService.shared.queue(contents: songs, group: group, position: position, startIndex: 0)
        }
    }
}

/// One album on the Recently Downloaded shelf: its cover, name and artist.
private struct OnDeviceAlbumTile: View {
    let album: OnDeviceLibrary.Group

    /// The cover's side: two and a bit across an iPhone, so the shelf
    /// shows it scrolls.
    private static let side: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Decoded at the tile's size: a Files cover is the file's own
            // embedded picture, often thousands of pixels across.
            LazyImage(request: album.artwork.map { url in
                var request = ImageRequest(url: url)
                request.thumbnail = .init(maxPixelSize: ContentArtworkView.maxPixelSize(for: Double(Self.side)))
                return request
            }) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay {
                            Image(systemName: OnDeviceCollection.albums.systemImage)
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: Self.side, height: Self.side)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(album.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.side, alignment: .leading)
        .contentShape(.rect)
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
