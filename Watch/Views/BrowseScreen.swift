import SwiftUI
import WatchKit
import WatchSync

/// A page of the Plex and Subsonic libraries, fetched by the watch itself
/// (`WatchLibraryBrowser`) a page at a time: a list, an artist's albums or
/// search results. A song goes on the watch with a tap; an album or
/// playlist opens on its songs.
struct BrowseScreen: View {
    let path: WatchBrowsePath

    @Environment(\.zoomNamespace) private var zoom
    @Environment(WatchDownloadStore.self) private var store
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
                .zoomSource(BrowseRoute.item(container), in: zoom)
            }

            ForEach(items) { item in
                row(for: item)
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
                    Button("Try Again") {
                        Task { await load(offset: 0) }
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
    }

    /// An artist opens on its albums; a song goes on the watch with a tap;
    /// an album or playlist opens on its songs.
    @ViewBuilder
    private func row(for item: WatchBrowseItem) -> some View {
        if let destination = item.destination {
            NavigationLink(value: BrowseRoute.path(destination)) {
                BrowseRow(item: item)
            }
            .zoomSource(BrowseRoute.path(destination), in: zoom)
        } else if let pick = item.pick, pick.kind == .song {
            Button {
                store.add(pick, songs: item.song.map { [$0] })
                WKInterfaceDevice.current().play(.success)
            } label: {
                BrowseRow(item: item)
            }
            .disabled(store.isOnWatch(pick))
        } else {
            NavigationLink(value: BrowseRoute.item(item)) {
                BrowseRow(item: item)
            }
            .zoomSource(BrowseRoute.item(item), in: zoom)
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

/// A row with its cover, ticked once it's on the watch — a song with a
/// download arrow until then.
private struct BrowseRow: View {
    @Environment(WatchDownloadStore.self) private var store
    let item: WatchBrowseItem

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: item.artworkURL)
                .frame(width: 32, height: 32)
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
            if let pick = item.pick {
                if store.isOnWatch(pick) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("On this watch")
                } else if pick.kind == .song {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// An album, playlist or artist from a server, with its songs: put it on
/// the watch whole, take it off, or put on single songs.
struct BrowseItemScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    let item: WatchBrowseItem

    @State private var songs: [WatchSong] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var note: String?

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

                if let pick = item.pick {
                    if store.picks.contains(key: pick.key) {
                        Label("On This Watch", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .listRowBackground(Color.clear)
                        Button(role: .destructive) {
                            store.remove(key: pick.key)
                            note = "Removed from this watch."
                        } label: {
                            Text("Remove from Watch")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        Button {
                            store.add(pick, songs: songs)
                            WKInterfaceDevice.current().play(.success)
                            note = songs.count == 1
                                ? "Downloading 1 song. Fast Download gets it here sooner."
                                : "Downloading \(songs.count) songs. Fast Download gets them here sooner."
                        } label: {
                            Label(songs.isEmpty ? "Download" : "Download \(songs.count) Songs", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(songs.isEmpty)
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
                } else if hasLoaded, songs.isEmpty {
                    Text("No songs, or the server can't be reached.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(songs) { song in
                    let isHere = store.isOnWatch(song.pick)
                    Button {
                        store.add(song.pick, songs: [song])
                        WKInterfaceDevice.current().play(.success)
                        note = "Downloading “\(song.title)”. It's in Songs."
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .lineLimit(2)
                                Text(song.artist)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: isHere ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                    }
                    .disabled(isHere)
                }
            } footer: {
                if !songs.isEmpty {
                    Text("Tap a song to put just that one on your watch.")
                }
            }
        }
        .task {
            guard !hasLoaded, let pick = item.pick else { return }
            isLoading = true
            songs = await WatchLibraryBrowser.shared.songs(for: pick) ?? []
            isLoading = false
            hasLoaded = true
        }
    }
}
