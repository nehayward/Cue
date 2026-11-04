import Foundation

/// Commands the dock menu can send back to the app. Plain `@objc` enum so it
/// crosses the MacGlue bundle boundary without bridging cost. They act on
/// whatever the player shows (`PlaybackRoute.presented`): this Mac or a
/// Sonos group.
@objc enum DockCommand: Int, CaseIterable {
    case playPause
    /// Previous, or back 15 seconds in a book.
    case previous
    /// Next, or forward 30 seconds in a book.
    case next
    case volumeUp
    case volumeDown
    case volumeUpLarge
    case volumeDownLarge
    /// Off, All, One, Off: the player's repeat button.
    case cycleRepeat
    case toggleShuffle
    case toggleCrossfade
    case toggleMute
    case muteAll
    case unmuteAll
    case toggleFavorite
    /// Brings Cue forward with the player open.
    case openPlayer
    /// Sleeps at the end of the song, or of the chapter in a book.
    case sleepAtEndOfItem
}

/// Everything the dock menu draws. The app builds it from the player and
/// sends it across the bundle boundary as JSON (`updateDockMenu(_:)`): a
/// Swift struct rather than an `@objc` class, because this file is compiled
/// into both the app and MacGlue, and two Objective-C classes of one name
/// would collide at runtime.
struct DockMenuState: Codable, Equatable {
    /// One place to play: this Mac or a Sonos group.
    struct Route: Codable, Equatable {
        /// `DockMenuState.deviceRouteID`, or the group's coordinator ID.
        var id: String
        var name: String
        var isCurrent: Bool
        /// Cue Super's: choosing it opens the paywall.
        var isLocked: Bool
    }

    enum RepeatMode: Int, Codable {
        case off, all, one
    }

    /// The id of This Mac in `routes`. Never a coordinator ID, which are
    /// `RINCON_…` room ids.
    static let deviceRouteID = "device"

    /// This Mac and each Sonos group. Empty with no speaker to choose, so
    /// the menu doesn't list This Mac on its own.
    var routes: [Route] = []

    // MARK: Sleep timer

    /// Something is loaded to put to sleep.
    var canSetSleepTimer = false
    /// When the timer goes off; nil with none set. The menu counts down from
    /// it as it opens, so it's never a stale number of minutes.
    var sleepEndsAt: Date?
    /// "End of Song", or "End of Chapter" for a book.
    var endOfItemTitle = "End of Song"
    var canSleepAtEndOfItem = false
    var sleepsAtEndOfItem = false

    // MARK: Playback

    /// Nil hides Repeat (nothing loaded, or a book).
    var repeatMode: RepeatMode?
    /// Nil hides Shuffle, as Repeat.
    var isShuffled: Bool?
    var canChangePlayMode = false
    var canShuffle = false
    /// Nil hides Crossfade: it's a speaker's setting, so only on a group.
    var isCrossfaded: Bool?

    // MARK: Volume

    /// The group's volume, 0–100. Nil hides the whole section: on this Mac
    /// the volume is macOS's.
    var volume: Int?
    var isVolumeFixed = false
    var isMuted = false
    /// Mute All Speakers and Unmute All Speakers: Cue Super, and more than
    /// one group to mute.
    var showsMuteAll = false

    // MARK: Now Playing

    /// "Title — Artist", or "Book — Chapter". Nil with nothing loaded.
    var nowPlaying: String?
    /// A line under it while a hand-off carries the song: "Moving to…".
    var nowPlayingNote: String?
    /// Only where the song's service can like it.
    var showsFavorite = false
    var isFavorite = false

    // MARK: Transport

    var isPlaying = false
    var canPlay = false
    /// "Previous", or "Back 15 Seconds" for a book. Nil hides it (a live
    /// station has nothing before it).
    var previousTitle: String?
    var canGoBack = false
    /// "Next", or "Forward 30 Seconds" for a book. Nil hides it.
    var nextTitle: String?
    var hasNext = false
}

/// The dock-menu surface the bundle exposes. Owned by `DockMenuRenderer`
/// inside MacGlue and consumed by `DockMenuCoordinator` on the app side.
/// Everything crosses the bundle boundary as ObjC-bridgeable types.
@objc(DockMenuRenderable)
protocol DockMenuRenderable: NSObjectProtocol {
    /// One-time setup: swizzles `applicationDockMenu(_:)` into the
    /// Catalyst-installed NSApplicationDelegate so right-clicking the dock
    /// icon shows our menu instead of Catalyst's default.
    func setupDockMenu()

    /// The whole menu, a `DockMenuState` encoded as JSON. Cheap: it's only
    /// kept, and drawn the next time the menu opens.
    func updateDockMenu(_ state: Data)

    func setDockCommandHandler(_ handler: @escaping (DockCommand) -> Void)
    /// Argument is the id of one of the `routes` last supplied.
    func setSwitchRouteHandler(_ handler: @escaping (String) -> Void)
    /// Argument is the sleep-timer duration in minutes; 0 cancels the timer.
    func setSleepTimerHandler(_ handler: @escaping (Int) -> Void)
    /// Fired each time the user opens the dock menu — a non-blocking hook for
    /// the app to read what it doesn't follow live, so the cache is current
    /// for the next open.
    func setMenuWillOpenHandler(_ handler: @escaping () -> Void)
}
