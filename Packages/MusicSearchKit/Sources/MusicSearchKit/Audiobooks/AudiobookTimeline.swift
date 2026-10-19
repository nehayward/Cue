import Foundation

/// A book's files laid end to end, so a place in the whole book — what a
/// listener means by "4 h 12 min in", and what Audiobookshelf stores as a
/// book's progress — maps to the file it falls in and how far into that
/// file, and back.
///
/// A book is one file (an `.m4b` with chapters inside) or many (a file per
/// chapter or per CD track). The player plays files; resume, chapters and
/// the book's progress bar all speak in book time.
public struct AudiobookTimeline: Sendable, Equatable, Codable {
    /// Each file's length in seconds, in playing order.
    public let partDurations: [TimeInterval]

    public init(partDurations: [TimeInterval]) {
        self.partDurations = partDurations.map { $0.isFinite ? max($0, 0) : 0 }
    }

    /// The whole book's length.
    public var duration: TimeInterval {
        partDurations.reduce(0, +)
    }

    /// Where file `index` starts in the book. Past the last file, the end.
    public func start(ofPart index: Int) -> TimeInterval {
        partDurations.prefix(max(index, 0)).reduce(0, +)
    }

    /// The file `time` falls in and the offset into it. A time on a
    /// boundary is the start of the later file, not the end of the earlier
    /// one, so resuming there doesn't open a file only to leave it. Before
    /// the start is the top of the first file; at or past the end is the
    /// end of the last.
    public func location(at time: TimeInterval) -> (part: Int, offset: TimeInterval) {
        guard !partDurations.isEmpty else { return (0, 0) }
        var start: TimeInterval = 0
        for (index, length) in partDurations.enumerated() {
            if time < start + length {
                return (index, max(time - start, 0))
            }
            start += length
        }
        let last = partDurations.count - 1
        return (last, partDurations[last])
    }

    /// The book time of `offset` seconds into file `part`, the inverse of
    /// `location(at:)`. The offset is held to the file's length.
    public func time(part: Int, offset: TimeInterval) -> TimeInterval {
        guard partDurations.indices.contains(part) else {
            return part < 0 ? 0 : duration
        }
        return start(ofPart: part) + min(max(offset, 0), partDurations[part])
    }
}

/// One chapter, in book time.
public struct AudiobookChapter: Sendable, Equatable, Codable, Identifiable, Hashable {
    /// Its place in the book, from zero.
    public let id: Int
    public let title: String
    /// Seconds into the whole book.
    public let start: TimeInterval
    public let end: TimeInterval

    public init(id: Int, title: String, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(end, start)
    }

    public var duration: TimeInterval { end - start }
}

public extension Array where Element == AudiobookChapter {
    /// The chapter playing at `time`: the last one starting at or before
    /// it. Nil before the first, or with no chapters.
    func chapter(at time: TimeInterval) -> AudiobookChapter? {
        last { $0.start <= time + AudiobookChapter.boundaryTolerance }
    }

    /// The chapter after the one playing at `time`: the first, before any
    /// has begun. Nil in the last chapter.
    func chapter(after time: TimeInterval) -> AudiobookChapter? {
        guard let current = chapter(at: time) else { return first }
        return first { $0.start > current.start }
    }

    /// Where Previous Chapter goes from `time`, as Previous goes for a
    /// song: back to the start of the chapter playing once a few seconds
    /// of it have been heard (`restartThreshold`), else to the start of the
    /// one before. Nil with no chapters.
    func previousChapterStart(from time: TimeInterval, restartThreshold: TimeInterval = 3) -> TimeInterval? {
        guard let current = chapter(at: time) else { return first.map { _ in 0 } }
        if time - current.start > restartThreshold { return current.start }
        return last { $0.start < current.start }?.start ?? current.start
    }

    /// A book's chapters from each file's own marks, laid on the book's
    /// timeline: a file with marks (an `.m4b`) gives them, offset to where
    /// the file starts; a file without gives one chapter named for it, so a
    /// book of a file per chapter reads the way it was ripped. A mark with
    /// no end runs to the next one, or the end of its file.
    static func from(files: [(title: String, marks: [AudiobookChapterMark])], timeline: AudiobookTimeline) -> [AudiobookChapter] {
        var chapters: [AudiobookChapter] = []
        for (index, file) in files.enumerated() {
            let start = timeline.start(ofPart: index)
            let end = start + (timeline.partDurations.indices.contains(index) ? timeline.partDurations[index] : 0)
            let marks = file.marks.sorted { $0.start < $1.start }
            if marks.isEmpty {
                chapters.append(AudiobookChapter(id: chapters.count, title: file.title, start: start, end: end))
                continue
            }
            for (markIndex, mark) in marks.enumerated() {
                let markStart = Swift.min(start + mark.start, end)
                let nextStart = markIndex + 1 < marks.count ? Swift.min(start + marks[markIndex + 1].start, end) : end
                let markEnd = mark.end.map { Swift.min(start + $0, end) } ?? nextStart
                let title = mark.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Chapter \(chapters.count + 1)"
                chapters.append(AudiobookChapter(id: chapters.count, title: title, start: markStart, end: markEnd))
            }
        }
        return chapters
    }

    /// One chapter per file, for a book whose files carry no chapter marks
    /// of their own: a file per chapter is how most rips are laid out, and
    /// the file's title is the chapter's.
    static func perPart(titles: [String], timeline: AudiobookTimeline) -> [AudiobookChapter] {
        titles.indices.compactMap { index in
            guard timeline.partDurations.indices.contains(index) else { return nil }
            let start = timeline.start(ofPart: index)
            return AudiobookChapter(id: index, title: titles[index], start: start, end: start + timeline.partDurations[index])
        }
    }
}

extension AudiobookChapter {
    /// How far before a chapter's start a time still counts as in it.
    /// Chapter marks are rounded to the millisecond, and a seek lands a
    /// fraction short; without this, jumping to a chapter showed the one
    /// before it.
    static let boundaryTolerance: TimeInterval = 0.25
}

/// A chapter mark inside one file, as the server or the file itself gives
/// it: seconds into that file.
public struct AudiobookChapterMark: Sendable, Equatable, Codable, Hashable {
    public let title: String?
    public let start: TimeInterval
    /// Nil when the mark doesn't say; it then runs to the next mark.
    public let end: TimeInterval?

    public init(title: String?, start: TimeInterval, end: TimeInterval? = nil) {
        self.title = title
        self.start = max(start, 0)
        self.end = end
    }
}

/// Where a listener is in a book.
public struct AudiobookProgress: Sendable, Equatable, Codable, Hashable {
    /// Seconds into the whole book.
    public var position: TimeInterval
    /// The book's length, as far as it's known; zero when it isn't.
    public var duration: TimeInterval
    public var isFinished: Bool
    /// When it was last listened to, or changed by hand. The newer of two
    /// readings — this device's and the server's — wins.
    public var updatedAt: Date

    public init(position: TimeInterval, duration: TimeInterval, isFinished: Bool = false, updatedAt: Date = .now) {
        self.position = max(position, 0)
        self.duration = max(duration, 0)
        self.isFinished = isFinished
        self.updatedAt = updatedAt
    }

    /// How much of the book has been heard, 0–1; nil with no length to
    /// measure against. A finished book is all of it.
    public var fraction: Double? {
        if isFinished { return 1 }
        guard duration > 0 else { return nil }
        return Swift.min(Swift.max(position / duration, 0), 1)
    }

    /// What's left to hear.
    public var remaining: TimeInterval {
        isFinished ? 0 : Swift.max(duration - position, 0)
    }

    /// Whether there's anywhere to resume: a book started and not finished.
    /// The first half minute is a sample, not a start.
    public var isStarted: Bool {
        !isFinished && position >= Self.startedThreshold
    }

    static let startedThreshold: TimeInterval = 30

    /// Where to start playing: back at the top for a finished book, else
    /// a few seconds before where it was left, so the listener hears the
    /// end of the sentence they stopped in again.
    public var resumePosition: TimeInterval {
        guard isStarted else { return 0 }
        return Swift.max(position - Self.resumeRewind, 0)
    }

    static let resumeRewind: TimeInterval = 5

    /// A listen counts as finished this close to the end: closing credits
    /// and the publisher's sign-off aren't worth waiting out.
    public static let finishedMargin: TimeInterval = 30

    /// The newer of two readings of the same book.
    public static func newer(_ a: AudiobookProgress?, _ b: AudiobookProgress?) -> AudiobookProgress? {
        guard let a else { return b }
        guard let b else { return a }
        return b.updatedAt > a.updatedAt ? b : a
    }
}
