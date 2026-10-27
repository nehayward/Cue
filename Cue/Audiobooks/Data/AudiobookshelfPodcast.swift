import Foundation
import MusicSearchKit
import SonosKit

/// A podcast on the Audiobookshelf server, as its list and its page show
/// it. Its episodes are books of one file (`PlayableContent.isPodcastEpisode`),
/// so they play, keep their place and download as books do; the podcast
/// itself only opens its page.
///
/// Public, as `RouterDestination` (public) carries it.
public struct AudiobookshelfPodcast: Hashable, Identifiable, Sendable {
    public let id: String
    let title: String
    var author: String?
    var episodeCount: Int?
    var summary: String?

    /// A podcast known only by its id and title: an episode's, before its
    /// page has read it.
    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(_ item: AudiobookshelfItem) {
        id = item.id
        let metadata = item.media?.metadata
        title = metadata?.title ?? ""
        author = metadata?.author.flatMap { $0.isEmpty ? nil : $0 }
        episodeCount = item.media?.numEpisodes ?? item.media?.episodes?.count
        summary = metadata?.description.map(AudiobookText.plain).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Its cover, as content `ContentArtworkView` draws.
    var artwork: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: author ?? "",
            thumbnail: AudiobookshelfAPI.coverURL(itemID: id, width: 300),
            artwork: AudiobookshelfAPI.coverURL(itemID: id),
            content: .init(service: .audiobookshelf, id: id, type: .album, location: nil),
            metadata: .init(albumID: id)
        )
    }

    /// "212 episodes".
    var episodeCountText: String? {
        guard let episodeCount, episodeCount > 0 else { return nil }
        return episodeCount == 1 ? "1 episode" : "\(episodeCount.formatted()) episodes"
    }
}

extension PlayableContent {
    /// An episode's line on its podcast's page: when it came out and how
    /// long it runs ("Oct 21, 2026 · 45m").
    var episodeDetail: String {
        var parts: [String] = []
        if let published = metadata?.albumYear {
            parts.append(published.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        if let duration = metadata?.duration, duration > .zero {
            parts.append(AudiobookFormat.duration(TimeInterval(duration.components.seconds)))
        }
        return parts.joined(separator: " · ")
    }
}
