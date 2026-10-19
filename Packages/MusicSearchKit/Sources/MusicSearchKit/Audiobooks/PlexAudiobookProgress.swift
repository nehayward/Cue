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

    /// The book's chapters. A file with chapter marks inside (an `.m4b`)
    /// gives its marks; a file without gives one chapter, named for the
    /// file — so a book of a file per chapter reads the way it was ripped.
    public static func chapters(parts: [PlexMetadata], timeline: AudiobookTimeline) -> [AudiobookChapter] {
        var chapters: [AudiobookChapter] = []
        for (index, part) in parts.enumerated() {
            let start = timeline.start(ofPart: index)
            let end = start + (timeline.partDurations[safe: index] ?? 0)
            let marks = (part.chapters ?? [])
                .compactMap { mark -> (title: String?, start: TimeInterval, end: TimeInterval?)? in
                    guard let offset = mark.startTimeOffset else { return nil }
                    return (mark.tag, TimeInterval(offset) / 1000, mark.endTimeOffset.map { TimeInterval($0) / 1000 })
                }
                .sorted { $0.start < $1.start }
            if marks.isEmpty {
                chapters.append(AudiobookChapter(id: chapters.count, title: part.title, start: start, end: end))
                continue
            }
            for (markIndex, mark) in marks.enumerated() {
                let markStart = start + mark.start
                // A mark without an end runs to the next one, or the file's.
                let nextStart = marks[safe: markIndex + 1].map { start + $0.start } ?? end
                let markEnd = mark.end.map { min(start + $0, end) } ?? nextStart
                let title = mark.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Chapter \(chapters.count + 1)"
                chapters.append(AudiobookChapter(id: chapters.count, title: title, start: markStart, end: markEnd))
            }
        }
        return chapters
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
