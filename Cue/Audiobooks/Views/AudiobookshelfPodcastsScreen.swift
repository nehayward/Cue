import MusicSearchKit
import SonosKit
import SwiftUI

/// Every podcast on the Audiobookshelf server, by title, each opening its
/// page; under each library's name when there are several.
struct AudiobookshelfPodcastsScreen: View {
    @State private var browse = AudiobookshelfBrowseService.shared
    /// Each podcast library's podcasts, by library id.
    @State private var podcasts: [String: [AudiobookshelfPodcast]] = [:]
    @State private var isLoading = false
    @State private var failed = false
    @State private var query = ""

    var body: some View {
        List {
            ForEach(browse.podcastLibraries) { library in
                let shown = matching(podcasts[library.id] ?? [])
                if !shown.isEmpty {
                    Section {
                        ForEach(shown) { podcast in
                            NavigationLink(value: RouterDestination.audiobookshelfPodcast(podcast)) {
                                AudiobookshelfPodcastRow(podcast: podcast)
                            }
                        }
                    } header: {
                        if browse.podcastLibraries.count > 1 {
                            Text(library.name)
                        }
                    }
                }
            }
        }
        .overlay {
            if podcasts.values.allSatisfy(\.isEmpty) {
                if isLoading {
                    ProgressView()
                } else if failed {
                    ContentUnavailableView {
                        Label("Couldn't Reach Audiobookshelf", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check that the server is running and reachable from here, then pull to refresh.")
                    }
                } else {
                    ContentUnavailableView("No Podcasts", systemImage: "mic", description: Text("Podcasts added to Audiobookshelf show here."))
                }
            }
        }
        .searchable(text: $query, prompt: "Podcasts")
        .fontDesign(.rounded)
        .navigationTitle("Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .miniPlayerOnScrollHandler()
    }

    /// The podcasts whose title or maker has `query` in it; all of them
    /// with none typed.
    private func matching(_ podcasts: [AudiobookshelfPodcast]) -> [AudiobookshelfPodcast] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return podcasts }
        return podcasts.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // Opened before the shelves were read: the libraries first.
        if browse.podcastLibraries.isEmpty {
            await browse.load()
        }
        var answered = false
        for library in browse.podcastLibraries {
            guard let found = await browse.podcasts(in: library) else { continue }
            answered = true
            podcasts[library.id] = found
        }
        failed = !answered && !browse.podcastLibraries.isEmpty
    }
}

/// A podcast's row: its cover, title, who makes it and how many episodes.
struct AudiobookshelfPodcastRow: View {
    let podcast: AudiobookshelfPodcast

    var body: some View {
        HStack(spacing: 14) {
            ContentArtworkView(content: podcast.artwork, showMusicSource: false, preferredSize: 200, cornerRadius: 6)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                if let author = podcast.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let count = podcast.episodeCountText {
                    Text(count)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
