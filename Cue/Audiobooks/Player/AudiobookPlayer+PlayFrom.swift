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

    /// `play(_:at:)` for a chapter or a place tapped in a list. When that
    /// moves the book more than `placeJump` from where it was, the Undo
    /// pill offers the old place back for a few seconds, so a tap on the
    /// wrong row costs nothing. It shows at the tap, not once the new place
    /// has loaded, and names where Undo goes: the chapter there, from
    /// `audiobook` (the book read whole, when it is), and the book's time.
    /// Not for CarPlay, whose chapters play with `play(chapter:)`: the pill
    /// is the phone's.
    func pick(_ book: PlayableContent, at time: TimeInterval, in audiobook: Audiobook?) async {
        if let from = place(of: book), abs(from - time) > Self.placeJump {
            let name = [audiobook?.chapter(at: from)?.title, AudiobookFormat.clock(from)]
                .compactMap { $0 }
                .joined(separator: " · ")
            UndoPill.shared.show(name) { [weak self] in
                Task { await self?.play(book, at: from) }
            }
        }
        await play(book, at: time)
    }

    /// Where `book` is: the loaded one as heard, any other as kept. Nil
    /// for one never started or finished, which has no place to go back to.
    private func place(of book: PlayableContent) -> TimeInterval? {
        if current?.book.isSameBook(as: book) == true { return heardPosition }
        guard let kept = AudiobookProgressStore.shared.progress(for: book), !kept.isFinished else { return nil }
        return kept.position
    }
}
