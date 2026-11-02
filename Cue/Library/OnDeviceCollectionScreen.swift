import Defaults
import Nuke
import NukeUI
import SonosKit
import SwiftUI

/// The on-device library's Albums, Artists or Playlists page: what's
/// here, grouped, with a local search and sort. A row opens the songs of
/// that album, artist or playlist that are on the device — no server is
/// asked — with a Play All that queues just those. Everything in the
/// Downloads tab and offline; one provider's songs from Settings ▸
/// Storage. Rows are drawn as a server's album list draws them, and
/// Albums can be a grid of covers, by the same List / Grid choice every
/// album list shares (`AppStorageKeys.albumsLayout`).
struct OnDeviceCollectionScreen: View {
    let collection: OnDeviceCollection
    var service: MusicService? = nil

    @AppStorage(AppStorageKeys.albumsLayout) private var layout: PlayableListLayout = .list
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.displayScale) private var displayScale
    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared
    @State private var searchText = ""
    /// Kept per page, as the library's other lists keep theirs.
    @AppStorage private var sort: OnDeviceLibrary.GroupSort
    @AppStorage private var isDescending: Bool

    init(collection: OnDeviceCollection, service: MusicService? = nil) {
        self.collection = collection
        self.service = service
        let key = "onDevice.\(collection.title.lowercased()).\(service?.sonosRawValue ?? "all")"
        _sort = AppStorage(wrappedValue: .title, "\(key).sort")
        _isDescending = AppStorage(wrappedValue: false, "\(key).descending")
    }

    var body: some View {
        // Read here so a download finishing or an index rebuilding re-runs
        // the grouping; the library itself is static.
        _ = downloads.musicSummary
        _ = apple.version
        _ = files.indexVersion
        let groups = OnDeviceLibrary.groups(collection, matching: searchText, sortedBy: sort, descending: isDescending, in: service)
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty

        return VStack(spacing: 0) {
            if isGrid {
                grid(groups)
            } else {
                list(groups)
            }
        }
        // A list of its own for each order, so a new sort lays the rows
        // out afresh rather than relying on the list to move them.
        .id("\(sort.rawValue).\(isDescending)")
        .overlay {
            if groups.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("Nothing on This Device", systemImage: "arrow.down.circle")
                    } description: {
                        Text(OnDeviceLibrary.emptyDescription(for: service))
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search \(collection.title)")
        .onAppear {
            apple.refreshIfNeeded()
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsGrid {
                // One tap flips the layout, the icon the layout a tap gives,
                // as on a server's album list.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        layout = layout.other
                    } label: {
                        Label("Show as \(layout.other.label)", systemImage: layout.other.systemImage)
                    }
                }
            }
            if !groups.isEmpty || isSearching {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(collection.title)
                            .font(.headline)
                        Text(collection.count(groups.count))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $sort) {
                            ForEach(OnDeviceLibrary.GroupSort.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        Picker("Order", selection: $isDescending) {
                            Text(sort == .added ? "Oldest First" : "A – Z").tag(false)
                            Text(sort == .added ? "Newest First" : "Z – A").tag(true)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onChange(of: sort) { _, newValue in
            // Each order starts in its own natural direction.
            isDescending = newValue == .added
        }
    }

    /// Albums only, as on a server: the covers are what you scan for.
    private var allowsGrid: Bool { collection == .albums }

    private var isGrid: Bool { allowsGrid && layout == .grid }

    /// Rows as a server's album list has them: tight, with no separators,
    /// the covers parting them.
    private func list(_ groups: [OnDeviceLibrary.Group]) -> some View {
        List {
            ForEach(groups) { group in
                NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
                    OnDeviceGroupRow(group: group, collection: collection)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .onDeviceRemoveActions(for: group.container)
            }
        }
        .listStyle(.plain)
    }

    /// As many tiles as fit, at least this wide, touching, as a server's
    /// album grid lays them (`PlayableListView`).
    private static let gridColumns = [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: 0)]

    /// The same albums as a wall of covers, nothing written under them: the
    /// title is a tap away. Each opens on its page; a long press removes it.
    private func grid(_ groups: [OnDeviceLibrary.Group]) -> some View {
        // One size a device class, as the server's grid asks for, so a
        // cover is decoded once whatever the tile's width.
        let artworkSize = (sizeClass == .compact ? 150.0 : 220.0) * min(displayScale, 3) / 3
        return ScrollView {
            LazyVGrid(columns: Self.gridColumns, spacing: 0) {
                ForEach(groups) { group in
                    NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                ContentArtworkView(
                                    content: group.container,
                                    showMusicSource: false,
                                    preferredSize: artworkSize,
                                    cornerRadius: 0,
                                    placeholderStyle: AnyShapeStyle(.quaternary)
                                )
                                .scaledToFill()
                            }
                            .clipped()
                            .contentShape(.rect)
                            // Nothing written on the tile, so VoiceOver reads
                            // the name.
                            .accessibilityLabel(group.title)
                    }
                    .buttonStyle(.plain)
                    .onDeviceRemoveActions(for: group.container)
                }
            }
        }
    }
}

/// One album or artist on the device: art, name, the line under it, and
/// for an album its song count. Shared by the grouped pages and the Search
/// tab's offline results.
struct OnDeviceGroupRow: View {
    let group: OnDeviceLibrary.Group
    let collection: OnDeviceCollection

    var body: some View {
        HStack(spacing: 12) {
            // Decoded at the row's size: a Files cover is the file's own
            // embedded picture, often 1500–3000 px — 9 to 36 MB once decoded
            // in full, for a 50 pt square.
            LazyImage(request: group.artwork.map { url in
                var request = ImageRequest(url: url)
                request.thumbnail = .init(maxPixelSize: ContentArtworkView.maxPixelSize(for: 50))
                return request
            }) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay {
                            Image(systemName: collection.systemImage)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(collection == .artists ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))

            // The library row's type (`PlayableContentView`).
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .lineLimit(1)
                Text(group.subtitle)
                    .font(.footnote)
                    .opacity(0.7)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if collection != .artists {
                Text(group.trackCount == 1 ? "1 song" : "\(group.trackCount) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    NavigationStack {
        OnDeviceCollectionScreen(collection: .albums)
    }
    .withEnvironments()
}
