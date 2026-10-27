import MusicSearchKit
import SonosKit
import SwiftUI

/// The podcasts followed by their feeds, and finding more: by name in
/// Apple's podcast directory (the search field), or by a feed's address.
/// A podcast's episodes play on this device or a speaker, each from where
/// it was left (`PodcastFeeds`, `AudiobookPlayer`). Audiobookshelf's
/// podcasts, when its server has any, are a row away.
struct PodcastsScreen: View {
    @Environment(Router.self) private var router
    @State private var feeds = PodcastFeeds.shared
    @State private var shelf = AudiobookshelfBrowseService.shared
    @State private var query = ""
    @State private var results: [PodcastFeeds.SearchResult]?
    @State private var isSearching = false
    /// The podcast being followed from a search result or an address.
    @State private var following: URL?
    @State private var isAddingAddress = false
    @State private var address = ""
    @State private var failure: String?

    private var isQuerying: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List {
            if isQuerying {
                searchResults
            } else {
                if shelf.isAuthenticated, !shelf.podcastLibraries.isEmpty {
                    Section {
                        NavigationLink(value: RouterDestination.audiobookshelfPodcasts) {
                            Label("On Audiobookshelf", systemImage: MusicService.audiobookshelfSymbolName)
                        }
                    }
                }
                followed
            }
        }
        .overlay {
            if !isQuerying, feeds.feeds.isEmpty {
                ContentUnavailableView {
                    Label("No Podcasts Yet", systemImage: MusicService.podcastsSymbolName)
                } description: {
                    Text("Find a podcast by name above, or add one by its feed's address. Its episodes play here or on your speakers, each from where you left it.")
                } actions: {
                    Button("Add by Address") { isAddingAddress = true }
                        .buttonStyle(.bordered)
                }
            }
        }
        .searchable(text: $query, prompt: "Find a Podcast")
        .autocorrectionDisabled()
        .task(id: query) { await search() }
        .task { await feeds.refresh() }
        .refreshable { await feeds.refresh(force: true) }
        .fontDesign(.rounded)
        .navigationTitle("Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingAddress = true
                } label: {
                    Label("Add by Address", systemImage: "link.badge.plus")
                }
            }
        }
        .alert("Add a Podcast", isPresented: $isAddingAddress) {
            TextField("Feed address", text: $address)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Add") {
                guard let url = PodcastFeeds.feedURL(from: address) else {
                    failure = "That isn't an address. A podcast's feed address usually ends in .xml, .rss or /feed."
                    return
                }
                address = ""
                Task { await follow(url) }
            }
            Button("Cancel", role: .cancel) { address = "" }
        } message: {
            Text("Paste the address of the podcast's RSS feed.")
        }
        .alert("Couldn't Add the Podcast", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .miniPlayerOnScrollHandler()
    }

    // MARK: - Followed

    @ViewBuilder
    private var followed: some View {
        if !feeds.feeds.isEmpty {
            Section {
                ForEach(feeds.feeds) { feed in
                    NavigationLink(value: RouterDestination.podcastFeed(id: feed.id)) {
                        PodcastFeedRow(title: feed.title, author: feed.author, artwork: feed.artworkContent, detail: feed.latestEpisodeLine)
                    }
                    .swipeActions {
                        Button("Unfollow", role: .destructive) {
                            feeds.unfollow(feed)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Following")
                    if feeds.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
        }
    }

    // MARK: - Finding

    @ViewBuilder
    private var searchResults: some View {
        if let results {
            if results.isEmpty {
                Text("No podcasts called that.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(results) { result in
                    Button {
                        Task { await open(result) }
                    } label: {
                        HStack {
                            PodcastFeedRow(
                                title: result.title,
                                author: result.author,
                                artwork: PodcastFeed.cover(id: result.id, title: result.title, url: result.artworkURL),
                                detail: result.episodeCount.map { $0 == 1 ? "1 episode" : "\($0.formatted()) episodes" }
                            )
                            Spacer(minLength: 0)
                            if following == result.feedURL {
                                ProgressView()
                            } else if feeds.isFollowing(result.feedURL) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Following")
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Follow")
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(following != nil)
                }
            } footer: {
                if !results.isEmpty {
                    Text("From Apple's podcast directory. A podcast is followed by its own feed.")
                }
            }
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    /// The directory, once typing pauses.
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            results = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isSearching = true
        let found = await feeds.search(term)
        guard !Task.isCancelled else { return }
        isSearching = false
        results = found ?? []
    }

    /// A result: its page, followed first if it isn't yet.
    private func open(_ result: PodcastFeeds.SearchResult) async {
        if feeds.isFollowing(result.feedURL) {
            router.navigate(to: .podcastFeed(id: PodcastFeed.id(for: result.feedURL)))
            return
        }
        await follow(result.feedURL)
    }

    private func follow(_ url: URL) async {
        following = url
        defer { following = nil }
        switch await feeds.follow(url) {
        case let .success(feed):
            HapticManager.shared.fireHaptic(.notification(.success))
            router.navigate(to: .podcastFeed(id: feed.id))
        case let .failure(error):
            failure = error.message
        }
    }
}

/// A podcast's row: its cover, title, who makes it, and a line under them.
struct PodcastFeedRow: View {
    let title: String
    let author: String?
    let artwork: PlayableContent
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            ContentArtworkView(content: artwork, showMusicSource: false, preferredSize: 200, cornerRadius: 6)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                if let author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

extension PodcastFeed {
    /// Its cover, as content `ContentArtworkView` draws.
    var artworkContent: PlayableContent {
        Self.cover(id: id, title: title, url: artworkURL)
    }

    /// A podcast's cover by its picture's address, as content.
    static func cover(id: String, title: String, url: URL?) -> PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: url,
            artwork: url,
            content: .init(service: .podcasts, id: id, type: .album, location: nil),
            metadata: .init(albumID: id)
        )
    }

    /// "Oct 21 · 212 episodes": when the newest came out, and how many.
    var latestEpisodeLine: String? {
        var parts: [String] = []
        if let newest = episodes.first?.published {
            parts.append(newest.formatted(.dateTime.month(.abbreviated).day()))
        }
        if !episodes.isEmpty {
            parts.append(episodes.count == 1 ? "1 episode" : "\(episodes.count.formatted()) episodes")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension PodcastFeeds {
    /// The newest episodes across every podcast followed, newest first.
    func latestEpisodes(limit: Int = 12) -> [PlayableContent] {
        feeds
            .flatMap { feed in feed.episodes.prefix(limit).map { (feed, $0) } }
            .sorted { ($0.1.published ?? .distantPast) > ($1.1.published ?? .distantPast) }
            .prefix(limit)
            .map { $0.1.toPlayable(in: $0.0) }
    }
}
