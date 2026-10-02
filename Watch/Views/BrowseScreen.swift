import SwiftUI
import WatchKit
import WatchSync

/// A page of the iPhone's libraries: its Plex and Subsonic servers, their
/// lists, and the albums, playlists and artists in them, asked of the
/// iPhone (`WatchBrowseServer`) a page at a time. An album or playlist
/// opens on a screen that puts it on the watch.
struct BrowseScreen: View {
    let path: WatchBrowsePath

    @State private var title = ""
    @State private var items: [WatchBrowseItem] = []
    @State private var container: WatchBrowseItem?
    @State private var nextOffset: Int?
    @State private var message: String?
    @State private var error: String?
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        List {
            if let container {
                NavigationLink(value: container) {
                    Label("Download All", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

            ForEach(items) { item in
                if let destination = item.destination {
                    NavigationLink(value: destination) {
                        BrowseRow(item: item)
                    }
                } else {
                    NavigationLink(value: item) {
                        BrowseRow(item: item)
                    }
                }
            }

            if let nextOffset, !isLoading, error == nil {
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
            } else if let error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await load(offset: nextOffset ?? 0) }
                    }
                }
                .listRowBackground(Color.clear)
            } else if let message, items.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(title)
        .task {
            guard !hasLoaded else { return }
            await load(offset: 0)
        }
    }

    private func load(offset: Int) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let reply = try await PhoneConnection.shared.request(.browse(path, offset: offset))
            switch reply {
            case let .page(page):
                hasLoaded = true
                title = page.title
                container = page.container
                message = page.message
                items = offset == 0 ? page.items : items + page.items.filter { new in !items.contains { $0.id == new.id } }
                nextOffset = page.nextOffset
            case let .failed(reason):
                error = reason
            case .added, .removed, .needsQuality:
                break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
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

/// An album, playlist or artist from the iPhone's library: put it on the
/// watch, or take it off. The first time, with no quality chosen on the
/// iPhone yet, it asks which.
struct BrowseItemScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    let item: WatchBrowseItem

    @State private var isWorking = false
    @State private var note: String?
    @State private var isChoosingQuality = false

    private var isOnWatch: Bool {
        item.collectionKey.map { store.library.collection(key: $0) != nil } ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ArtworkView(url: item.artworkURL)
                    .frame(width: 90, height: 90)
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

                if let content = item.content {
                    if isOnWatch {
                        Label("On This Watch", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                        Button(role: .destructive) {
                            send(.remove(content))
                        } label: {
                            Text("Remove from Watch")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isWorking)
                    } else {
                        Button {
                            send(.add(content, quality: nil))
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                    }
                }

                if isWorking {
                    ProgressView()
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isChoosingQuality) {
            QualityPicker { quality in
                isChoosingQuality = false
                if let content = item.content {
                    send(.add(content, quality: quality))
                }
            }
        }
    }

    private func send(_ request: WatchRequest) {
        guard !isWorking else { return }
        isWorking = true
        note = nil
        Task {
            defer { isWorking = false }
            do {
                switch try await PhoneConnection.shared.request(request) {
                case let .added(songs):
                    WKInterfaceDevice.current().play(.success)
                    note = songs == 1
                        ? "Downloading 1 song. Fast Download gets it here sooner."
                        : "Downloading \(songs) songs. Fast Download gets them here sooner."
                case .removed:
                    note = "Removed from this watch."
                case .needsQuality:
                    isChoosingQuality = true
                case let .failed(reason):
                    WKInterfaceDevice.current().play(.failure)
                    note = reason
                case .page:
                    break
                }
            } catch {
                WKInterfaceDevice.current().play(.failure)
                note = error.localizedDescription
            }
        }
    }
}

/// Which quality songs come down at, asked the first time something goes
/// on the watch from here. Saved on the iPhone, where it can be changed.
private struct QualityPicker: View {
    let choose: (WatchDownloadQuality) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WatchDownloadQuality.allCases) { quality in
                        Button {
                            choose(quality)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(quality == .recommended ? "\(quality.title) (Recommended)" : quality.title)
                                Text(quality.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Your watch has much less room than your iPhone, so songs can be converted to MP3 as they download. Change it later in Cue on your iPhone.")
                }
            }
            .navigationTitle("Quality")
        }
    }
}
