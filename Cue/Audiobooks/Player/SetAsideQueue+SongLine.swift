import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

extension LocalPlaybackService.SetAsideQueue {
    /// The song it was on, and who it's by, under the album or playlist it
    /// came from (`title`); just who it's by when the title is the song's.
    /// Where You Left Off and CarPlay's Your Music both show it.
    var songLine: String? {
        guard let song = nowPlaying else { return nil }
        let artist = song.metadata?.artist ?? song.subtitle
        let parts = title == song.title ? [artist] : [song.title, artist]
        let line = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// How many songs are left from the one it was on, for Where You Left
    /// Off. Nil with a station in front of the queue, which `songLine`
    /// names instead.
    var queueLine: String? {
        let left = queue.count - index
        guard station == nil, left > 0 else { return nil }
        return left == 1 ? "1 song in queue" : "\(left) songs in queue"
    }
}
