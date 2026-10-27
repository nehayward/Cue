import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

extension PlayableContent {
    /// Who wrote the book: its artist, else its subtitle up to what's left
    /// of it ("Andy Weir • 5 hr, 3 min left"). Nil when neither says.
    var bookAuthor: String? {
        let name = metadata?.artist ?? subtitle.components(separatedBy: " • ").first
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The book with what's left of it added to its subtitle ("Andy Weir •
    /// 5 hr, 3 min left"), for a shelf's rows.
    func withAudiobookProgress(_ progress: AudiobookProgress?) -> PlayableContent {
        guard let progress, let remaining = AudiobookFormat.remaining(progress) else { return self }
        let subtitle = [subtitle, remaining].filter { !$0.isEmpty }.joined(separator: " • ")
        return PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            artwork: artwork,
            content: content,
            previewURL: previewURL,
            metadata: metadata
        )
    }
}

extension PlayableContent {
    /// The same book, wherever the copy came from: by its server and id,
    /// as `AudiobookProgressStore` keys it.
    func isSameBook(as other: PlayableContent?) -> Bool {
        guard let other else { return false }
        return content.service == other.content.service && content.id == other.content.id
    }
}

extension PlayableContent {
    /// A podcast's episode, which plays as a book of one file: one followed
    /// by its feed (`PodcastFeeds`), or an Audiobookshelf podcast's
    /// (`AudiobookshelfMediaKey`). It has a podcast where a book has an
    /// author, and nothing on Audible.
    var isPodcastEpisode: Bool {
        switch content.service {
        case .podcasts: true
        case .audiobookshelf: AudiobookshelfMediaKey(content.id).isEpisode
        default: false
        }
    }

    /// The podcast an episode is from: its feed's id, or its item id on the
    /// Audiobookshelf server.
    var podcastID: String? {
        switch content.service {
        case .podcasts:
            String(PodcastIDs.episodeID(ofPart: content.id).prefix { $0 != PodcastIDs.separator })
        case .audiobookshelf where isPodcastEpisode:
            AudiobookshelfMediaKey(content.id).itemID
        default:
            nil
        }
    }

    /// The page of the podcast an episode is from.
    var podcastDestination: RouterDestination? {
        guard let podcastID else { return nil }
        if content.service == .podcasts {
            return .podcastFeed(id: podcastID)
        }
        return .audiobookshelfPodcast(AudiobookshelfPodcast(id: podcastID, title: subtitle))
    }
}
