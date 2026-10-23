import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

extension AudiobookPlayer {
    /// Plays the loaded book from `chapter`'s start.
    func play(chapter: AudiobookChapter) async {
        await playLoaded(from: chapter.start)
    }

    /// Plays the loaded book from book time `time`: a chapter or a place
    /// picked is meant to be heard, so a paused book starts there, where a
    /// skip leaves it paused. A move to another file starts playing by
    /// itself; a seek within the file playing doesn't.
    func playLoaded(from time: TimeInterval) async {
        guard let current else { return }
        let controller = PlaybackRoute.shared.controller
        let wasPlaying = controller.isPlaying
        let staysInFile = current.partIndex(of: controller.nowPlayingDisplay) == current.timeline.location(at: time).part
        await jump(to: time)
        if !wasPlaying, staysInFile {
            await controller.togglePlayback()
        }
    }

    /// Plays `book` from book time `time`: the loaded one from there, any
    /// other read from its server and started there.
    func play(_ book: PlayableContent, at time: TimeInterval) async {
        if current?.book.isSameBook(as: book) == true {
            await playLoaded(from: time)
        } else {
            await play(book, from: time)
        }
    }
}
