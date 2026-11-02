import Foundation

/// What Cue's player shows, as Cue (Mac) sends it to Cue Mini: the song or
/// book `PlaybackRoute.presented` is on, where it plays, its clock and what
/// its controls can do.
///
/// Compiled into both apps (Cue (Mac) and Cue Mini, by membership
/// exceptions on the `Mac` folder), so it's Foundation alone. Cue sends it
/// as JSON in the object of a distributed notification
/// (`changedNotification`) whenever something in it changes
/// (`CueMiniLink`), never on a timer, and again when Mini asks
/// (`CueMiniCommand.refresh`, as Mini launches and as its menu opens). The
/// cover goes on its own (`CueMiniCover`), once per cover.
///
/// Notifications rather than a file in the App Group: Cue Mini's
/// provisioning profile doesn't authorize `group.dance.cue`, and on macOS
/// 15 and later a container the profile doesn't cover asks the user's
/// leave first. A sandboxed app's distributed notification can carry a
/// string object but no user info.
///
/// Mini runs the clock itself from `Clock.readAt`, so nothing is sent for
/// the bar to move; Cue sends again only when the clock is corrected (a
/// seek, a pause, a song).
struct CueMiniNowPlaying: Codable, Equatable, Sendable {
    /// Bumped on a change an older reader would get wrong. Mini ignores a
    /// state of another version rather than drawing it.
    static let currentVersion = 1

    var version = Self.currentVersion
    /// The Cue that sent it. Mini believes it only while that Cue runs.
    var processID: Int32
    var sentAt: Date
    /// Nil with nothing loaded.
    var item: Item?
    var clock: Clock
    var isPlaying: Bool
    /// The controls have something to act on: false with nothing loaded,
    /// and while a hand-off holds the player on its source.
    var isActive: Bool
    /// Play was asked for and hasn't started: a load, a speaker
    /// transitioning, a hand-off.
    var isLoading: Bool
    var route: Route
    var transport: Transport
    var isShuffled: Bool
    var repeatMode: RepeatMode
    /// Cue's Settings ▸ Sonos ▸ Use Sonos Speakers. Mini leaves the
    /// speakers alone, without looking for them, while it's off.
    var sonosEnabled: Bool

    struct Item: Codable, Equatable, Sendable {
        /// The playing item's id, which a seek names so it can't land on
        /// the song after.
        var id: String
        /// The song; for a book with chapters, the chapter.
        var title: String
        /// The artist; for a book, the book (under its chapter) or its author.
        var subtitle: String
        /// The cover's `CueMiniCover.key`; nil for an item without one.
        var artworkKey: String?
        /// A book: ±15/30 s skips replace Previous and Next
        /// (`Transport.skipBack`, `skipForward`).
        var isBook: Bool
    }

    /// The bar. For a book with chapters it spans the chapter playing, as
    /// the player's scrubber does (`AudiobookPlayer.chapterSpan`), so its
    /// times are from `spanStart` in the file.
    struct Clock: Codable, Equatable, Sendable {
        /// Seconds the bar spans; zero for a live stream, which has none.
        var duration: TimeInterval
        /// Seconds into the bar at `readAt`.
        var position: TimeInterval
        var readAt: Date
        /// Whether the position is moving.
        var isRunning: Bool
        /// How fast it moves: a book's speed on this Mac, else 1.
        var rate: Double
        /// Where the bar starts in the file playing, which a seek adds back.
        var spanStart: TimeInterval

        /// Seconds into the bar at `date`.
        func position(at date: Date) -> TimeInterval {
            guard isRunning else { return position }
            let running = position + max(date.timeIntervalSince(readAt), 0) * rate
            return duration > 0 ? min(running, duration) : running
        }
    }

    struct Route: Codable, Equatable, Sendable {
        /// "This Mac", or the speaker group's name.
        var name: String
        /// The group's coordinator (a RINCON id, as SonosKitMini's
        /// `SonosDevice.id`); nil for this Mac.
        var groupID: String?
        var roomCount: Int
        /// Where a hand-off is taking the song while it runs.
        var movingTo: String?

        var isSpeaker: Bool { groupID != nil }
    }

    struct Transport: Codable, Equatable, Sendable {
        var showsPrevious: Bool
        var canGoBack: Bool
        var showsNext: Bool
        var hasNext: Bool
        var canScrub: Bool
        /// A book's skips, in seconds, in Previous's and Next's places.
        var skipBack: TimeInterval?
        var skipForward: TimeInterval?
        /// Shuffle and Repeat mean something: not for a book or a live
        /// station.
        var showsPlayModes: Bool
    }

    enum RepeatMode: String, Codable, Sendable {
        case off, all, one

        /// Off, all, one, off: the order the player's button goes in.
        var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    /// Cue (Mac)'s bundle id, which Mini watches for and opens.
    static let cueBundleIdentifier = "dance.cue"
    /// Posted by Cue (through MacGlue), the state as JSON in its object.
    static let changedNotification = "dance.cue.mini.nowPlaying"
}

/// The cover of the item on show, sent apart from the state and only when
/// it changes (or Mini asks): a small JPEG, which Mini can draw without
/// reaching the server it came from (a Plex server's, MusicKit's).
struct CueMiniCover: Codable, Equatable, Sendable {
    /// What it's the cover of, as `CueMiniNowPlaying.Item.artworkKey`.
    var key: String
    /// About 120 px square; base64 in the JSON.
    var jpeg: Data

    /// Posted by Cue (through MacGlue), the cover as JSON in its object.
    static let notificationName = "dance.cue.mini.cover"
}

/// What Cue Mini asks Cue's player to do, sent as a distributed
/// notification (`notificationName`) with the command as JSON in its
/// object. Cue (Mac) runs it on `PlaybackRoute.presented`.
enum CueMiniCommand: Codable, Equatable, Sendable {
    case togglePlayback
    case next
    case previous
    /// A book's ±15/30 s.
    case skip(seconds: TimeInterval)
    /// To `seconds` in the file playing, if it's still `itemID`.
    case seek(seconds: TimeInterval, itemID: String)
    case setShuffle(Bool)
    case setRepeat(CueMiniNowPlaying.RepeatMode)
    /// Send the state now, clock and cover and all: Mini launched, or its
    /// menu opened.
    case refresh

    static let notificationName = "dance.cue.mini.command"
}

/// What goes between Cue and Cue Mini: JSON in a distributed
/// notification's string object, both ways.
protocol CueMiniMessage: Codable {}

extension CueMiniNowPlaying: CueMiniMessage {}
extension CueMiniCover: CueMiniMessage {}
extension CueMiniCommand: CueMiniMessage {}

extension CueMiniMessage {
    var notificationObject: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    init?(notificationObject object: Any?) {
        guard let string = object as? String, let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }
}
