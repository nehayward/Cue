import MusicSearchKit
import SonosKit
import SwiftUI

/// A followed podcast's page: its cover, who makes it and what it's about,
/// then its episodes newest first, each with how far in it is and its own
/// Play. An episode's row opens its page (`AudiobookDetailView`, as a
/// book's), with its chapters, its bookmarks and Download. The feed is
/// read again as the page opens, at most once an hour (`PodcastFeeds`).
struct PodcastFeedScreen: View {
    let feedID: String

    @Environment(\.dismiss) private var dismiss
    @State private var feeds = PodcastFeeds.shared
    @State private var query = ""
    @State private var isRefreshing = false

    var body: some View {
        if let feed = feeds.feed(id: feedID) {
            content(feed)
        } else {
            ContentUnavailableView("Not Following", systemImage: MusicService.podcastsSymbolName, description: Text("This podcast isn't followed any more."))
        }
    }

    private func content(_ feed: PodcastFeed) -> some View {
        let episodes = feed.episodes.map { $0.toPlayable(in: feed) }
        return List {
            Section {
                header(feed)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(matching(episodes)) { episode in
                    AudiobookContinueRow(book: episode, subtitle: episode.episodeDetail)
                }
            } header: {
                if !episodes.isEmpty {
                    HStack {
                        Text("Episodes")
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .overlay {
            if episodes.isEmpty {
                ContentUnavailableView("No Episodes", systemImage: MusicService.podcastsSymbolName, description: Text("This feed has no episodes with audio in it."))
            }
        }
        .searchable(text: $query, prompt: "Episodes")
        .fontDesign(.rounded)
        .navigationTitle(feed.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await refresh(feed) }
                    } label: {
                        Label("Check for New Episodes", systemImage: "arrow.clockwise")
                    }
                    ShareLink(item: feed.url) {
                        Label("Share Feed", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        feeds.unfollow(feed)
                        dismiss()
                    } label: {
                        Label("Unfollow", systemImage: "minus.circle")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .refreshable { await refresh(feed) }
        .task {
            guard Date.now.timeIntervalSince(feed.checkedAt ?? .distantPast) > PodcastFeeds.refreshInterval else { return }
            await refresh(feed)
        }
        .miniPlayerOnScrollHandler()
    }

    private func header(_ feed: PodcastFeed) -> some View {
        VStack(spacing: 10) {
            ContentArtworkView(content: feed.artworkContent, showMusicSource: false, preferredSize: ContentArtworkView.playerPreferredSize, cornerRadius: 8)
                .frame(width: 200, height: 200)
            Text(feed.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            if let author = feed.author {
                Text(author)
                    .foregroundStyle(.secondary)
            }
            if let line = feed.latestEpisodeLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            if let summary = feed.summary.map(AudiobookText.plain), !summary.isEmpty {
                AudiobookSummary(text: summary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The episodes whose title has `query` in it; all of them with none
    /// typed.
    private func matching(_ episodes: [PlayableContent]) -> [PlayableContent] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return episodes }
        return episodes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func refresh(_ feed: PodcastFeed) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await feeds.refresh(feed)
    }
}
