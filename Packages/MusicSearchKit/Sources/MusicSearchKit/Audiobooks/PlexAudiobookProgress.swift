import Foundation

/// Reading a Plex book's files as one book: its timeline, its chapters, and
/// where it was left.
public enum PlexAudiobook {
    /// The files laid end to end, by their lengths.
    public static func timeline(parts: [PlexMetadata]) -> AudiobookTimeline {
        AudiobookTimeline(partDurations: parts.map(length))
    }

    /// A file's length in seconds: the track's, else its media's.
    static func length(of part: PlexMetadata) -> TimeInterval {
        let milliseconds = part.duration ?? part.media?.first?.duration ?? 0
        return TimeInterval(milliseconds) / 1000
    }

    /// The book's chapters: each file's marks (an `.m4b`'s), from `marks`
    /// by the file's rating key where they were read on their own (from
    /// Plex, or from the file itself), else as the file's metadata carries
    /// them; a file without gives one chapter named for it (see
    /// `[AudiobookChapter].from(files:timeline:)`).
    public static func chapters(parts: [PlexMetadata], marks: [String: [AudiobookChapterMark]] = [:], timeline: AudiobookTimeline) -> [AudiobookChapter] {
        let files = parts.map { part in
            (title: part.title, marks: marks[part.ratingKey] ?? chapterMarks(part.chapters ?? []))
        }
        return .from(files: files, timeline: timeline)
    }

    /// Plex's chapter marks as book chapter marks: offsets in milliseconds
    /// into the file. A mark with no start is dropped.
    public static func chapterMarks(_ chapters: [PlexChapter]) -> [AudiobookChapterMark] {
        chapters.compactMap { mark in
            guard let offset = mark.startTimeOffset else { return nil }
            return AudiobookChapterMark(
                title: mark.tag,
                start: TimeInterval(offset) / 1000,
                end: mark.endTimeOffset.map { TimeInterval($0) / 1000 }
            )
        }
    }

    /// Where the book was left, from what Plex keeps for each file: the file
    /// listened to last, partway (`viewOffset`) or played through (then
    /// the start of the next). Nil for a book never started. Every file
    /// played means the book is finished.
    public static func progress(parts: [PlexMetadata], timeline: AudiobookTimeline) -> AudiobookProgress? {
        guard !parts.isEmpty else { return nil }
        let duration = timeline.duration
        if parts.allSatisfy({ ($0.viewCount ?? 0) > 0 && ($0.viewOffset ?? 0) == 0 }) {
            let lastViewed = parts.compactMap(\.lastViewedAt).max()
            return AudiobookProgress(position: duration, duration: duration, isFinished: true, updatedAt: date(lastViewed))
        }
        // The file touched last. A file partway through with no date (an
        // older server) still says where the listener is.
        let latest = parts.indices.max { lhs, rhs in
            (parts[lhs].lastViewedAt ?? 0) < (parts[rhs].lastViewedAt ?? 0)
        }
        let partway = parts.indices.first { (parts[$0].viewOffset ?? 0) > 0 }
        guard let index = parts[latest ?? 0].lastViewedAt != nil ? latest : partway else { return nil }

        let part = parts[index]
        let position: TimeInterval
        if let offset = part.viewOffset, offset > 0 {
            position = timeline.time(part: index, offset: TimeInterval(offset) / 1000)
        } else if (part.viewCount ?? 0) > 0 {
            position = timeline.start(ofPart: index + 1)
        } else {
            position = timeline.start(ofPart: index)
        }
        return AudiobookProgress(
            position: position,
            duration: duration,
            isFinished: position >= duration && duration > 0,
            updatedAt: date(part.lastViewedAt)
        )
    }

    private static func date(_ seconds: Int?) -> Date {
        seconds.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast
    }
}
