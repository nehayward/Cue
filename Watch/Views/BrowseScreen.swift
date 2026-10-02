import SwiftUI
import WatchKit
import WatchSync

/// A page of the Plex and Subsonic libraries, fetched by the watch itself
/// (`WatchLibraryBrowser`) a page at a time: the servers, their lists, and
/// the albums, playlists and artists in them. An album or playlist opens on
/// its songs, to put on the watch whole or one at a time.
struct BrowseScreen: View {
    let path: WatchBrowsePath

    @Environment(WatchAccounts.self) private var accounts
    @State private var title = ""
    @State private var items: [WatchBrowseItem] = []
    @State private var container: WatchBrowseItem?
    @State private var nextOffset: Int?
    @State private var message: String?
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        List {
            if let container {
                NavigationLink(value: BrowseRoute.item(container)) {
                    Label("All Songs", systemImage: "music.note.list")
                        .foregroundStyle(.tint)
                }
            }

            ForEach(items) { item in
                NavigationLink(value: item.destination.map(BrowseRoute.path) ?? .item(item)) {
                    BrowseRow(item: item)
                }
            }

            if let nextOffset, !isLoading {
                Button("More") {
                    Task { await load(offset: nextOffset) }
                }
                .onAppear {
                    Task { await load(offset: nextOffset) }
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if let message, items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if path != .root {
                        Button("Try Again") {
                            Task { await load(offset: 0) }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(title)
        .task {
            guard !hasLoaded else { return }
            await load(offset: 0)
        }
        // New sign-ins from the iPhone: the list of servers changes.
        .onChange(of: accounts.hasAny) {
            guard path == .root else { return }
            Task { await load(offset: 0) }
        }
    }

    private func load(offset: Int) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let page = await WatchLibraryBrowser.shared.page(path, offset: offset)
        hasLoaded = true
        title = page.title
        container = page.container
        message = page.message
        items = offset == 0 ? page.items : items + page.items.filter { new in !items.contains { $0.id == new.id } }
        nextOffset = page.nextOffset
    }
}

/// Where a browse row goes: another page, or an album, playlist or artist's
/// songs.
enum BrowseRoute: Hashable {
    case path(WatchBrowsePath)
    case item(WatchBrowseItem)
}

/// A row: a place (with its symbol) or music (with its cover), ticked once
/// it's on the watch.
private struct BrowseRow: View {
    @Environment(WatchDownloadStore.self) private var store
    let item: WatchBrowseItem

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
            } else {
                ArtworkView(url: item.artworkURL)
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading) {
                Text(item.title)
                    .lineLimit(2)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let key = item.collectionKey, store.library.collection(key: key) != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("On this watch")
            }
        }
    }
}

/// An album, playlist or artist from a server, with its songs: put it on
/// the watch whole, take it off, or put on single songs. The first time,
/// with no quality chosen yet, it asks which.
struct BrowseItemScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    let item: WatchBrowseItem

    @State private var tracks: [WatchTrack] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var note: String?
    /// What to do once a quality is picked.
    @State private var awaitingQuality: QualityPurpose?

    private enum QualityPurpose: Identifiable {
        case all
        case song(WatchTrack)

        var id: String {
            switch self {
            case .all: "all"
            case let .song(track): track.key
            }
        }
    }

    private var isOnWatch: Bool {
        item.collectionKey.map { store.library.collection(key: $0) != nil } ?? false
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    ArtworkView(url: item.artworkURL)
                        .frame(width: 80, height: 80)
                    Text(item.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

                if item.content != nil {
                    if isOnWatch {
                        Label("On This Watch", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .listRowBackground(Color.clear)
                        Button(role: .destructive) {
                            if let key = item.collectionKey {
                                store.removeCollection(key: key)
                                note = "Removed from this watch."
                            }
                        } label: {
                            Text("Remove from Watch")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        Button {
                            perform(.all)
                        } label: {
                            Label(tracks.isEmpty ? "Download" : "Download \(tracks.count) Songs", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tracks.isEmpty)
                        .listRowBackground(Color.clear)
                    }
                }

                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if hasLoaded, tracks.isEmpty {
                    Text("No songs, or the server can't be reached.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(tracks) { track in
                    Button {
                        perform(.song(track))
                    } label: {
                        SongRow(track: track, isHere: store.library.tracks[track.key] != nil)
                    }
                    .disabled(store.library.tracks[track.key] != nil)
                }
            } footer: {
                if !tracks.isEmpty {
                    Text("Tap a song to put just that one on your watch.")
                }
            }
        }
        .task {
            guard !hasLoaded, let content = item.content else { return }
            isLoading = true
            tracks = await WatchLibraryBrowser.shared.tracks(for: content, quality: store.library.effectiveQuality)
            isLoading = false
            hasLoaded = true
        }
        .sheet(item: $awaitingQuality) { purpose in
            QualityPicker { quality in
                awaitingQuality = nil
                store.setQuality(quality)
                perform(purpose)
            }
        }
    }

    private func perform(_ purpose: QualityPurpose) {
        guard let content = item.content else { return }
        guard let quality = store.library.quality else {
            awaitingQuality = purpose
            return
        }
        let converted = tracks.map { $0.converted(to: quality) }
        switch purpose {
        case .all:
            guard !converted.isEmpty else { return }
            let collection = WatchLibraryBrowser.shared.collection(for: content, tracks: converted, addedAt: .now)
            store.add(collection, tracks: converted)
            note = converted.count == 1
                ? "Downloading 1 song. Fast Download gets it here sooner."
                : "Downloading \(converted.count) songs. Fast Download gets them here sooner."
        case let .song(track):
            store.addSongs([track.converted(to: quality)])
            note = "Downloading “\(track.title)”. It's in Songs."
        }
        WKInterfaceDevice.current().play(.success)
    }
}

private struct SongRow: View {
    let track: WatchTrack
    let isHere: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading) {
                Text(track.title)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: isHere ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }
}

/// Which quality songs come down at — asked the first time something goes
/// on the watch, and changed from the library screen.
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
