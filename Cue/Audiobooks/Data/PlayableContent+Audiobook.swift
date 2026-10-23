import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

extension PlayableContent {
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
