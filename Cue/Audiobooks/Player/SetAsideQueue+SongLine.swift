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
}
