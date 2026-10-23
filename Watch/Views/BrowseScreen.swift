import MusicSearchKit
import SwiftUI
import WatchKit
import WatchSync

/// A page of the Plex and Subsonic libraries, or of the books on Plex and
/// Audiobookshelf, fetched by the watch itself (`WatchLibraryBrowser`) a
/// page at a time: a list, an artist's albums, search results or a shelf of
/// books. A song plays with a tap (the page's songs from it) and goes on
/// the watch with a swipe; an album or playlist opens on its songs, a book
/// on its page.
struct BrowseScreen: View {
    let path: WatchBrowsePath

    @Environment(\.zoomNamespace) private var zoom
    @Environment(WatchDownloadStore.self) private var store
    @State private var playOn = PlayOn()
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
        .playOnSheet(playOn)
        .task {
            guard !hasLoaded else { return }
            await load(offset: 0)
        }
    }

    /// An artist opens on its albums; a song plays with a tap and goes on
    /// the watch with a swipe; an album or playlist opens on its songs.
    @ViewBuilder
    private func row(for item: WatchBrowseItem) -> some View {
        if let destination = item.destination {
            NavigationLink(value: BrowseRoute.path(destination)) {
                BrowseRow(item: item)
            }
            .zoomSource(BrowseRoute.path(destination), in: zoom)
        } else if let pick = item.pick, pick.kind == .song {
            Button {
                play(item)
            } label: {
                BrowseRow(item: item)
            }
            .swipeActions(edge: .trailing) {
                if !store.isOnWatch(pick) {
                    Button {
                        store.add(pick, songs: item.song.map { [$0] })
                        WKInterfaceDevice.current().play(.success)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(Color.accentColor)
                }
            }
        } else {
            NavigationLink(value: BrowseRoute.item(item)) {
                BrowseRow(item: item)
            }
            .zoomSource(BrowseRoute.item(item), in: zoom)
        }
    }

    /// The page's songs from this one. A Plex search result doesn't carry
    /// its file, so it's looked up and plays alone.
    private func play(_ item: WatchBrowseItem) {
        if let song = item.song {
            playOn.play(items.compactMap(\.song), startingAt: song.key)
        } else if let pick = item.pick {
            Task {
                guard let songs = await WatchLibraryBrowser.shared.songs(for: pick), !songs.isEmpty else {
                    WKInterfaceDevice.current().play(.failure)
                    return
                }
                playOn.play(songs)
            }
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

/// A row with its cover, ticked once it's on the watch.
private struct BrowseRow: View {
    @Environment(WatchDownloadStore.self) private var store
    let item: WatchBrowseItem

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: item.artworkURL, symbol: item.pick?.kind == .audiobook ? "book.closed" : "music.note")
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
            if let pick = item.pick, store.isOnWatch(pick) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("On this watch")
            }
        }
    }
}

/// An album, playlist or artist from a server, with its songs: play or
/// shuffle it (each song from the watch when it's downloaded, streamed
/// when it isn't), put it on the watch whole, or take it off. A song plays
/// with a tap and goes on the watch on its own with a swipe.
struct BrowseItemScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    let item: WatchBrowseItem

    @State private var songs: [WatchSong] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var note: String?
    @State private var playOn = PlayOn()

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

                actions
                    .listRowBackground(Color.clear)

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
                        playOn.play(songs, startingAt: song.key)
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .lineLimit(2)
                                    .foregroundStyle(player.current?.key == song.key ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                Text(song.artist)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isHere {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("On this watch")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !isHere {
                            Button {
                                store.add(song.pick, songs: [song])
                                WKInterfaceDevice.current().play(.success)
                                note = "Downloading “\(song.title)”. It's in Songs."
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .tint(Color.accentColor)
                        }
                    }
                }
            } footer: {
                if !songs.isEmpty {
                    Text("Tap a song to play it. Swipe left on it to download just that one.")
                }
            }

            if let pick = item.pick, store.picks.contains(key: pick.key) {
                Section {
                    Button(role: .destructive) {
                        store.remove(key: pick.key)
                        note = "Removed from this watch."
                    } label: {
                        Text("Remove from Watch")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .playOnSheet(playOn)
        .task {
            guard !hasLoaded, let pick = item.pick else { return }
            isLoading = true
            songs = await WatchLibraryBrowser.shared.songs(for: pick) ?? []
            isLoading = false
            hasLoaded = true
        }
    }

    /// Play, Shuffle and Download, as symbols. Download is the prominent
    /// one, and a tick once it's all on the watch.
    private var actions: some View {
        HStack {
            Button {
                playOn.play(songs)
            } label: {
                Image(systemName: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Play")
            .primaryHandGesture()
            Button {
                playOn.play(songs, shuffled: true)
            } label: {
                Image(systemName: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Shuffle")
            if let pick = item.pick {
                let isHere = store.picks.contains(key: pick.key)
                Button {
                    store.add(pick, songs: songs)
                    WKInterfaceDevice.current().play(.success)
                    note = songs.count == 1
                        ? "Downloading 1 song. Fast Download gets it here sooner."
                        : "Downloading \(songs.count) songs. Fast Download gets them here sooner."
                } label: {
                    Image(systemName: isHere ? "checkmark" : "arrow.down")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isHere)
                .accessibilityLabel(isHere ? "On This Watch" : songs.count == 1 ? "Download 1 Song" : "Download \(songs.count) Songs")
            }
        }
        .buttonStyle(.bordered)
        .disabled(songs.isEmpty)
    }
}

/// A book from a server: how long it is and where the server has the
/// listener, and Download Book to put it on the watch — or, once it's
/// here, the way to its page.
struct BrowseBookScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(\.zoomNamespace) private var zoom
    let item: WatchBrowseItem

    @State private var book: WatchBookLookup?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var note: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    ArtworkView(url: item.artworkURL, symbol: "book.closed")
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
                    if let book {
                        Text(detail(of: book))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

                if let pick = item.pick {
                    if store.picks.contains(key: pick.key) {
                        let route = BookRoute(key: pick.key)
                        NavigationLink(value: route) {
                            Label("On This Watch", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        .zoomSource(route, in: zoom)
                    } else {
                        Button {
                            add(pick)
                        } label: {
                            Label("Download Book", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(book == nil)
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

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if hasLoaded, book == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't read this book, or the server can't be reached.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
    }

    /// Its length, and where the server has the listener when they've
    /// started it.
    private func detail(of book: WatchBookLookup) -> String {
        let length = WatchBookFormat.length(book.duration)
        guard let place = book.serverPlace, place.isStarted || place.isFinished else { return length }
        return "\(length) • \(WatchBookFormat.status(place, duration: book.duration))"
    }

    private func load() async {
        guard let pick = item.pick, !isLoading else { return }
        isLoading = true
        book = await WatchLibraryBrowser.shared.book(for: pick)
        isLoading = false
        hasLoaded = true
    }

    /// Puts the book on the watch with the files and chapters just read.
    private func add(_ pick: WatchPick) {
        guard let book else { return }
        store.add(pick, songs: book.songs)
        WatchBookStore.shared.noteLookedUp(book, for: pick)
        WKInterfaceDevice.current().play(.success)
        note = "Downloading. Fast Download gets it here sooner."
    }
}
