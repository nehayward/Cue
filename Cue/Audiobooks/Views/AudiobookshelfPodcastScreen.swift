import MusicSearchKit
import SonosKit
import SwiftUI

/// A podcast's page: its cover, who makes it and what it's about, then its
/// episodes newest first, each with how far in it is and its own Play. An
/// episode's row opens its page (`AudiobookDetailView`, as a book's), with
/// its chapters, its history and Download.
struct AudiobookshelfPodcastScreen: View {
    let podcast: AudiobookshelfPodcast

    /// The podcast as the server read it as the page opened.
    @State private var loaded: AudiobookshelfPodcast?
    @State private var episodes: [PlayableContent] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var query = ""

    var body: some View {
        let shown = loaded ?? podcast
        List {
            Section {
                header(shown)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(matching(episodes)) { episode in
                    AudiobookContinueRow(book: episode, subtitle: episode.episodeDetail)
                }
            } header: {
                if !episodes.isEmpty {
                    Text("Episodes")
                }
            }
        }
        .overlay {
            if episodes.isEmpty {
                if isLoading {
                    ProgressView()
                } else if failed {
                    ContentUnavailableView {
                        Label("Couldn't Open This Podcast", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check that Audiobookshelf is reachable, then pull to refresh.")
                    }
                } else {
                    ContentUnavailableView("No Episodes", systemImage: "mic", description: Text("This podcast's episodes haven't been downloaded to the server yet."))
                }
            }
        }
        .searchable(text: $query, prompt: "Episodes")
        .fontDesign(.rounded)
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .miniPlayerOnScrollHandler()
    }

    private func header(_ shown: AudiobookshelfPodcast) -> some View {
        VStack(spacing: 10) {
            ContentArtworkView(content: shown.artwork, showMusicSource: false, preferredSize: ContentArtworkView.playerPreferredSize, cornerRadius: 8)
                .frame(width: 200, height: 200)
            Text(shown.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            if let author = shown.author {
                Text(author)
                    .foregroundStyle(.secondary)
            }
            if let count = shown.episodeCountText {
                Text(count)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            if let summary = shown.summary {
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let read = await AudiobookshelfBrowseService.shared.podcast(id: podcast.id) else {
            failed = true
            return
        }
        failed = false
        loaded = read.podcast
        episodes = read.episodes
    }
}
