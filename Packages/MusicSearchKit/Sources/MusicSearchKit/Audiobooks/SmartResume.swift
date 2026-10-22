import Foundation

/// Smart Resume, after Overcast's: a book played again after a pause goes
/// back a little first, so the listener hears again the words the pause cut
/// off — a moment after a short pause, more after a long one, to pick the
/// thread up again. Never back past the start of the chapter it paused in.
public enum SmartResume {
    /// How far back a book goes after a pause of `pause` seconds.
    public static func rewind(afterPausing pause: TimeInterval) -> TimeInterval {
        steps.first { pause < $0.pause }?.rewind ?? longestRewind
    }

    /// Where a book paused at `time` (book time) plays again from after a
    /// pause of `pause` seconds: back by `rewind(afterPausing:)`, held to
    /// the start of the chapter it paused in and of the book.
    public static func resumeTime(from time: TimeInterval, afterPausing pause: TimeInterval, chapters: [AudiobookChapter] = []) -> TimeInterval {
        // Just short of a chapter's start reads as that chapter
        // (`boundaryTolerance`): it stays put rather than move forward.
        let chapterStart = min(chapters.chapter(at: time)?.start ?? 0, time)
        return max(time - rewind(afterPausing: pause), chapterStart, 0)
    }

    /// Up to each length of pause, how far back.
    private static let steps: [(pause: TimeInterval, rewind: TimeInterval)] = [
        (10, 1),
        (60, 2),
        (5 * 60, 3),
        (60 * 60, 5),
        (24 * 60 * 60, 10),
    ]
    /// After a day or more.
    private static let longestRewind: TimeInterval = 15
}
