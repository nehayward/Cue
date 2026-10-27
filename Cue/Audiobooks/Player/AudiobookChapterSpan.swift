import Foundation
import SonosKit

extension AudiobookPlayer {
    /// What the player's scrubber spans while a book plays: the chapter
    /// playing, as Apple Books has it, in the file's own time (where the
    /// scrubber's position and its seeks are), cut to the file where a
    /// chapter runs on into the next one. A whole 20-hour `.m4b` across the
    /// bar put a minute under a pixel. Nil for anything but a book, a book
    /// without chapters, or a chapter that's the whole file: the scrubber
    /// spans the file then.
    func chapterSpan(on controller: any PlaybackController) -> ClosedRange<TimeInterval>? {
        guard let current, current.chapters.count > 1, let chapter = currentChapter,
              let part = current.partIndex(of: controller.nowPlayingDisplay) else { return nil }
        let timeline = current.timeline
        guard timeline.partDurations.indices.contains(part) else { return nil }
        let fileStart = timeline.start(ofPart: part)
        let fileLength = timeline.partDurations[part]
        let lower = min(max(chapter.start - fileStart, 0), fileLength)
        let upper = min(max(chapter.end - fileStart, 0), fileLength)
        // Under a second: nothing to scrub. The whole file: the plain bar.
        guard upper - lower >= 1, lower > 0.5 || upper < fileLength - 0.5 else { return nil }
        return lower...upper
    }
}
