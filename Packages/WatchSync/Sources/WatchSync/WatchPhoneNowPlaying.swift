import Foundation

/// What Cue on the iPhone is playing, for the watch's home and its player
/// of the iPhone's playback: the song (or the book, by its author, with the
/// chapter playing), where it plays — the iPhone or a Sonos group — whether
/// it's playing, which way it can skip, its place in the queue, its clock
/// (the time into the song, or a book's chapter, against its length), the
/// sleep timer, and a small copy of the cover. The iPhone sends it while
/// the watch app is open, as it changes, and in answer to the watch asking
/// (`WatchSyncMessage`). The clock runs on, on the watch, from when it was
/// read (`elapsed(at:)`); the iPhone sends it again when it moves any other
/// way (a seek, a skip, a new chapter).
public struct WatchPhoneNowPlaying: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String?
    /// Where it plays: the iPhone's name, or the Sonos group's.
    public var destination: String
    /// On a Sonos group rather than the iPhone itself.
    public var isOnSpeaker: Bool
    public var isPlaying: Bool
    /// One of the iPhone's books: Previous and Next skip back 15 s and
    /// ahead 30 s, as on the iPhone's player.
    public var isBook: Bool
    /// Previous does something: none for a live station.
    public var canGoBack: Bool
    /// Next does something: none at the end of the queue or on a live
    /// station.
    public var hasNext: Bool
    /// The song's place in the queue, from 1; zero while it isn't playing
    /// from one (a station in front of it, a speaker on radio or TV).
    public var queuePosition: Int
    /// How many songs the queue holds: zero for none, which leaves the
    /// watch's player without Up Next.
    public var queueCount: Int
    /// The cover as a small JPEG, made on the iPhone: the watch can't
    /// always reach the cover's own URL (a speaker's, a server's).
    public var artwork: Data?
    /// Seconds into the song — for a book with chapters, into the chapter;
    /// without, into the book — when it was read (`clockAt`). Nil for none
    /// to show (a live station).
    public var elapsed: Double?
    /// The song's length, or the chapter's (the book's, without chapters).
    /// Nil or zero for a live station, which has no bar.
    public var duration: Double?
    /// When `elapsed` was read, for the clock to run on from.
    public var clockAt: Date?
    /// How fast it plays: a book's speed on the iPhone itself, else 1.
    public var rate: Double
    /// The chapter playing, for a book with chapters.
    public var chapter: String?
    /// Its place in the book's chapters (`WatchPhoneChapters`), from zero.
    public var chapterID: Int?
    /// Where the chapter starts in the book (zero without chapters), so
    /// the clock gives the book's time too (`bookTime(at:)`).
    public var chapterStart: Double?
    /// The book's pick key, as the watch's picks name it: the same book on
    /// both, whether or not it's on the watch.
    public var bookKey: String?
    /// When the sleep timer pauses it; nil for no timer, or one at the end
    /// of the song.
    public var sleepsAt: Date?
    /// The sleep timer pauses at the end of the song, or a book's chapter.
    public var sleepsAtEnd: Bool

    public init(title: String, artist: String? = nil, destination: String, isOnSpeaker: Bool = false, isPlaying: Bool, isBook: Bool = false, canGoBack: Bool = true, hasNext: Bool = true, queuePosition: Int = 0, queueCount: Int = 0, artwork: Data? = nil, elapsed: Double? = nil, duration: Double? = nil, clockAt: Date? = nil, rate: Double = 1, chapter: String? = nil, chapterID: Int? = nil, chapterStart: Double? = nil, bookKey: String? = nil, sleepsAt: Date? = nil, sleepsAtEnd: Bool = false) {
        self.title = title
        self.artist = artist
        self.destination = destination
        self.isOnSpeaker = isOnSpeaker
        self.isPlaying = isPlaying
        self.isBook = isBook
        self.canGoBack = canGoBack
        self.hasNext = hasNext
        self.queuePosition = queuePosition
        self.queueCount = queueCount
        self.artwork = artwork
        self.elapsed = elapsed
        self.duration = duration
        self.clockAt = clockAt
        self.rate = rate
        self.chapter = chapter
        self.chapterID = chapterID
        self.chapterStart = chapterStart
        self.bookKey = bookKey
        self.sleepsAt = sleepsAt
        self.sleepsAtEnd = sleepsAtEnd
    }

    private enum CodingKeys: String, CodingKey {
        case title, artist, destination, isOnSpeaker, isPlaying, isBook, canGoBack, hasNext, queuePosition, queueCount, artwork
        case elapsed, duration, clockAt, rate, chapter, chapterID, chapterStart, bookKey, sleepsAt, sleepsAtEnd
    }

    /// An iPhone a version behind sends no skips: music, both ways open;
    /// nor a queue, which it can't send either; nor a clock, a chapter or a
    /// sleep timer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        destination = try container.decode(String.self, forKey: .destination)
        isOnSpeaker = try container.decode(Bool.self, forKey: .isOnSpeaker)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        isBook = try container.decodeIfPresent(Bool.self, forKey: .isBook) ?? false
        canGoBack = try container.decodeIfPresent(Bool.self, forKey: .canGoBack) ?? true
        hasNext = try container.decodeIfPresent(Bool.self, forKey: .hasNext) ?? true
        queuePosition = try container.decodeIfPresent(Int.self, forKey: .queuePosition) ?? 0
        queueCount = try container.decodeIfPresent(Int.self, forKey: .queueCount) ?? 0
        artwork = try container.decodeIfPresent(Data.self, forKey: .artwork)
        elapsed = try container.decodeIfPresent(Double.self, forKey: .elapsed)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        clockAt = try container.decodeIfPresent(Date.self, forKey: .clockAt)
        rate = try container.decodeIfPresent(Double.self, forKey: .rate) ?? 1
        chapter = try container.decodeIfPresent(String.self, forKey: .chapter)
        chapterID = try container.decodeIfPresent(Int.self, forKey: .chapterID)
        chapterStart = try container.decodeIfPresent(Double.self, forKey: .chapterStart)
        bookKey = try container.decodeIfPresent(String.self, forKey: .bookKey)
        sleepsAt = try container.decodeIfPresent(Date.self, forKey: .sleepsAt)
        sleepsAtEnd = try container.decodeIfPresent(Bool.self, forKey: .sleepsAtEnd) ?? false
    }

    /// The length the bar spans; nil for none (a live station, an iPhone a
    /// version behind).
    public var barLength: Double? {
        guard let duration, duration > 0, elapsed != nil else { return nil }
        return duration
    }

    /// Seconds into the song (or chapter) at `date`: the clock run on from
    /// when it was read while it plays, held while it's paused, and kept
    /// within the length.
    public func elapsed(at date: Date) -> Double? {
        guard let elapsed else { return nil }
        var time = elapsed
        if isPlaying, let clockAt {
            time += max(date.timeIntervalSince(clockAt), 0) * rate
        }
        if let duration, duration > 0 {
            time = min(time, duration)
        }
        return max(time, 0)
    }

    /// When the song (or chapter) began, by the clock running at `rate`:
    /// the bar runs on its own from here to `end(from:)` while it plays.
    public func startDate(at date: Date) -> Date? {
        guard let time = elapsed(at: date) else { return nil }
        return date.addingTimeInterval(-time / max(rate, 0.1))
    }

    /// Where a book is at `date`, in book time; nil for anything else.
    public func bookTime(at date: Date) -> Double? {
        guard isBook, let time = elapsed(at: date) else { return nil }
        return (chapterStart ?? 0) + time
    }

    /// Whether the sleep timer is set, either way.
    public var hasSleepTimer: Bool {
        sleepsAtEnd || (sleepsAt.map { $0 > .now } ?? false)
    }
}

/// Where the iPhone plays what the watch asks it to
/// (`WatchSyncMessage.playBookRequest`, `playItemRequest`).
public enum WatchPhoneTarget: Hashable, Sendable {
    /// The iPhone itself, whatever its player's route: the route comes back
    /// to it.
    case iPhone
    /// Where the iPhone's player plays now, a Sonos group as it may be.
    case route
    /// A Sonos group, by its coordinator's id (`WatchPhoneRoutes.Route.id`):
    /// the route goes there.
    case group(String)

    /// As a request carries it.
    public var key: String {
        switch self {
        case .iPhone: "iPhone"
        case .route: "route"
        case let .group(id): "group:\(id)"
        }
    }

    public init?(key: String) {
        switch key {
        case "iPhone": self = .iPhone
        case "route": self = .route
        case _ where key.hasPrefix("group:"): self = .group(String(key.dropFirst("group:".count)))
        default: return nil
        }
    }

    /// The route a target names, as `WatchPhoneRoutes` lists them; nil for
    /// wherever it plays now.
    public var routeID: String? {
        switch self {
        case .iPhone: WatchPhoneRoutes.iPhoneID
        case .route: nil
        case let .group(id): id
        }
    }

    public init(routeID: String) {
        self = routeID == WatchPhoneRoutes.iPhoneID ? .iPhone : .group(routeID)
    }
}

/// Where the iPhone can play, for the watch's Play On: the iPhone itself and
/// each Sonos group it reaches (none while Sonos is off or out of reach;
/// without Cue Super, only the free group), with the one its player is on.
/// Asked for as Play On opens (`WatchSyncMessage.routesRequest`); a tap
/// moves what plays there (`switchRouteRequest`), or plays a watch book or
/// album there (`WatchPhoneTarget.group`).
public struct WatchPhoneRoutes: Codable, Equatable, Sendable {
    public struct Route: Codable, Equatable, Sendable, Identifiable {
        /// `iPhoneID`, or the group's coordinator id.
        public var id: String
        public var name: String

        public var isSpeaker: Bool { id != WatchPhoneRoutes.iPhoneID }

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// The iPhone itself, among the routes.
    public static let iPhoneID = "iPhone"

    public var routes: [Route]
    /// The route the iPhone's player is on.
    public var current: String?

    public init(routes: [Route], current: String?) {
        self.routes = routes
        self.current = current
    }
}

/// The sleep timer the watch sets on the iPhone's playback.
public enum WatchPhoneSleep: Codable, Equatable, Sendable {
    case off
    /// At the end of the song, or of a book's chapter.
    case end
    case minutes(Int)
}

/// The chapters of the book the iPhone plays, for the watch's player of
/// it: asked for as its chapters open (`WatchSyncMessage.chaptersRequest`);
/// a tap plays one (`playChapterRequest`). Times are book time.
public struct WatchPhoneChapters: Codable, Equatable, Sendable {
    public struct Chapter: Codable, Equatable, Sendable, Identifiable {
        /// Its place in the book, from zero.
        public var id: Int
        public var title: String
        public var start: Double
        public var end: Double

        public var duration: Double { max(end - start, 0) }

        public init(id: Int, title: String, start: Double, end: Double) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
        }
    }

    /// The book's pick key (`WatchPhoneNowPlaying.bookKey`).
    public var bookKey: String?
    public var chapters: [Chapter]

    public init(bookKey: String?, chapters: [Chapter]) {
        self.bookKey = bookKey
        self.chapters = chapters
    }
}

/// A press on the watch's player for the iPhone's playback, carried out by
/// the iPhone on what its player shows (`PlaybackRoute.presented`).
public enum WatchPhoneCommand: String, Sendable, CaseIterable {
    case togglePlayPause
    /// The song before, or back 15 s in a book.
    case previous
    /// The next song, or ahead 30 s in a book.
    case next
}
