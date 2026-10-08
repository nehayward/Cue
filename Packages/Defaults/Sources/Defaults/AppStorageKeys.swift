import Foundation

public enum AppStorageKeys {
    /// Whether Cue looks for Sonos speakers at all. Cue is a player first,
    /// and looking for speakers is what puts up the Local Network prompt, so
    /// a new install starts with this off. It is turned on from Settings ▸
    /// Sonos (or onboarding). Read and written through
    /// `SonosService.isEnabled`, never directly: unset is decided there, and
    /// only the iOS and Mac app reads this key at all.
    public static let sonosEnabled = "\(Prefix.id).sonosEnabled"
    /// The search's selected services as one ordered comma-separated list,
    /// primary first (up to 3). Replaced the split `mediaService` +
    /// `searchAlsoServices` keys — deliberately not migrated; the selection
    /// resets once and users re-pick.
    public static let selectedSearchServices = "\(Prefix.id).selectedSearchServices"
    public static let browseMediaService = "\(Prefix.id).browseMediaService"
    /// The sidebar edits the system lets the user make to the provider tabs
    /// on iPad and Mac — hiding and reordering — as a `TabViewCustomization`.
    public static let tabViewCustomization = "\(Prefix.id).tabViewCustomization"
    /// The Files provider's folder, as a security-scoped bookmark (`Data`)
    /// of the folder the user picked — on this device or in iCloud Drive.
    public static let filesFolderBookmark = "\(Prefix.id).filesFolderBookmark"
    /// That folder's name, kept beside the bookmark so the Services row can
    /// name it without resolving the bookmark first.
    public static let filesFolderName = "\(Prefix.id).filesFolderName"
    /// Whether the download manager may fetch over cellular data. Off when
    /// unset: a whole album on a phone plan is a surprise nobody asked for.
    public static let downloadsOverCellular = "\(Prefix.id).downloadsOverCellular"
    /// Whether the download manager has looked for Plex conversions an
    /// earlier build kept cut short — done once (`repairCutShortDownloads`).
    public static let downloadsCutShortRepaired = "\(Prefix.id).downloadsCutShortRepaired"
    /// How Plex and Subsonic hand audio over — the original file, or
    /// transcoded on the server to MP3 or Opus (`"original"`, `"mp3"`,
    /// `"opus"`) — and the bitrate cap in kbit/s for a transcode. Read by
    /// `MusicSearchKit.StreamTranscoding`, which carries the same literal
    /// keys (it doesn't depend on this package): change one, change both.
    public static let streamTranscodeFormat = "\(Prefix.id).streamTranscodeFormat"
    public static let streamTranscodeBitrate = "\(Prefix.id).streamTranscodeBitrate"
    /// The playback cache: how many recently played songs to keep (0 is
    /// off), how many upcoming ones to fetch ahead, and whether to fill it
    /// over cellular.
    public static let playbackCacheSongLimit = "\(Prefix.id).playbackCacheSongLimit"
    public static let playbackCachePrefetchCount = "\(Prefix.id).playbackCachePrefetchCount"
    public static let playbackCacheOverCellular = "\(Prefix.id).playbackCacheOverCellular"
    /// Whether a Files folder in iCloud Drive is streamed: songs fetched as
    /// they come up and taken off the device again once they drop out of
    /// the playback cache. On when unset.
    public static let filesStreamFromCloud = "\(Prefix.id).filesStreamFromCloud"
    /// Whether the tags of Files songs still in iCloud are read by fetching
    /// just their headers, on Wi‑Fi. On when unset.
    public static let filesReadCloudTags = "\(Prefix.id).filesReadCloudTags"
    /// The iCloud songs the cache fetched to play, oldest first, so a
    /// relaunch still knows which ones are its to evict.
    public static let playbackCacheCloudIDs = "\(Prefix.id).playbackCacheCloudIDs"
    /// The user's Offline Mode switch: only what's on this device shows on
    /// Home, and everything plays here. Off when unset; no network at all
    /// puts the app in the same state on its own.
    public static let offlineMode = "\(Prefix.id).offlineMode"
    /// Whether the Radio tab shows at all. On when unset; the tab also
    /// needs a radio provider switched on, and hides itself offline.
    public static let showRadioTab = "\(Prefix.id).showRadioTab"
    /// How the library's album lists are laid out — `"list"` (rows) or
    /// `"grid"` (artwork tiles). One setting for every provider's Albums
    /// page, so a choice made on Plex holds on Subsonic. Rows when unset.
    public static let albumsLayout = "\(Prefix.id).albumsLayout"
    public static let appleMusicAuthorized = "\(Prefix.id).appleMusicAuthorized"
    public static let colorScheme = "\(Prefix.id).colorScheme"
    public static let speedLaunchNowPlaying = "\(Prefix.id).speedLaunchNowPlaying"
    public static let queueMode = "\(Prefix.id).queueMode"
    public static let showArtworkOnly = "\(Prefix.id).showArtworkOnly"
    public static let queueInspectorVisible = "\(Prefix.id).queueInspectorVisible"
    /// Width in points of the trailing queue panel, so a drag-to-resize
    /// survives relaunch.
    public static let queuePanelWidth = "\(Prefix.id).queuePanelWidth"
    /// The app's own output level for local playback, 0...1, where the
    /// device's volume can't be driven (Mac Catalyst). On iOS the slider is
    /// the system volume and nothing is stored.
    public static let localPlaybackVolume = "\(Prefix.id).localPlaybackVolume"
    /// Where the device queue is — track index, seconds in, duration, repeat
    /// mode — so a relaunch picks up the track that was playing where it
    /// was. The queue itself is a file in Application Support.
    public static let localQueuePosition = "\(Prefix.id).localQueuePosition"
    /// What the device queue was played from — the album, playlist or folder
    /// the Play came from — so the player can name its origin the way the
    /// Sonos player names the speaker's container, across a relaunch.
    public static let localQueueSource = "\(Prefix.id).localQueueSource"
    /// Whether the player shows Live Transcription, so the toggle holds
    /// across launches.
    public static let liveTranscriptionEnabled = "\(Prefix.id).liveTranscriptionEnabled"
    /// The transcription language picked per station — `[TuneIn station id:
    /// locale identifier]` — with `LiveTranscriptionService.anyStationKey`
    /// holding the last pick, the guess for a station not heard before.
    public static let liveTranscriptionLocales = "\(Prefix.id).liveTranscriptionLocales"
    /// Whether the player shows the song's lyrics in the artwork's place,
    /// so the toggle holds from song to song and across launches.
    public static let lyricsShown = "\(Prefix.id).lyricsShown"
    /// Whether a song whose own service has no timed lyrics is looked up
    /// on LRCLIB (sending its title, artist, album and length). Off unless
    /// turned on.
    public static let lyricsOnlineLookup = "\(Prefix.id).lyricsOnlineLookup"
    public static let savedGroupID = "\(Prefix.id).queueInspectorGroupID"
    public static let defaultPlayAction = "\(Prefix.id).defaultPlayAction"
    /// What switching the route (This Device ↔ a speaker) does with what's
    /// playing: `"ask"`, `"always"` (carry the queue across) or `"never"`
    /// (only change where the next Play goes). Asks when unset.
    public static let routeQueueTransfer = "\(Prefix.id).routeQueueTransfer"
    /// The Play On sheet's fitted height from earlier opens — `[layout:
    /// points]` — so it opens at its height rather than growing to it once
    /// the rows are measured.
    public static let playOnSheetHeights = "\(Prefix.id).playOnSheetHeights"
    public static let lastPlaylistID = "\(Prefix.id).lastPlaylistID"
    public static let lastPlaylistTitle = "\(Prefix.id).lastPlaylistTitle"
    public static let lastPlaylistService = "\(Prefix.id).lastPlaylistService"
    public static let recentPlaylistIDs = "\(Prefix.id).recentPlaylistIDs"
    /// Plex collections most recently added to, most recent first, for the
    /// Add to Collection sheet.
    public static let recentPlexCollectionIDs = "\(Prefix.id).recentPlexCollectionIDs"
    public static let addToPlaylistSegment = "\(Prefix.id).addToPlaylistSegment"
    public static let recentlyViewed = "\(Prefix.id).recentlyViewed"
    public static let recentQueries = "\(Prefix.id).recentQueries"
    public static let lastSeenWhatsNewVersion = "\(Prefix.id).lastSeenWhatsNewVersion"
    public static let lastSeenSettingsBadgeVersion = "\(Prefix.id).lastSeenSettingsBadgeVersion"
    public static let latestReleaseVersion = "\(Prefix.id).latestReleaseVersion"
    public static let latestReleaseHeadline = "\(Prefix.id).latestReleaseHeadline"
    /// The device's volume buttons — and the Lock Screen / Control Center
    /// slider, which are the same system volume — control the Sonos group
    /// instead of this device. **On** when unset: it's what people expect of a
    /// speaker controller, and the surface it drives (`Preferences ▸ Lock
    /// Screen ▸ Now Playing`) is itself the default with Super.
    ///
    /// It means one thing in both places that read it: *while Cue is your Lock
    /// Screen player, this device's volume controls the speaker.* Both the Lock
    /// Screen path and the player screen's `hardwareVolumeControl` therefore
    /// require `lockScreenNowPlaying` and an active subscription as well —
    /// don't add a reader that takes this key on its own. The row that sets it
    /// is shown only under Now Playing and only with Super, so a behaviour
    /// gated more loosely than the switch is one the user can't reach a control
    /// for.
    ///
    /// Read it through `UserDefaults.hardwareVolumeButtonsEnabled`, never
    /// `bool(forKey:)`, which reads unset as off and would leave the default
    /// unreachable.
    ///
    /// Defaulting this on is only safe because `HardwareVolumeService` stands
    /// the bridge down on any route that isn't the phone's own speaker, and
    /// refuses a volume jump larger than a hand could make. Read
    /// `Docs/LockScreenNowPlaying.md` § "Where the phone is" before weakening
    /// either — the report that produced them was a Sonos pair left at 100%
    /// volume all day.
    public static let useHardwareVolumeButtons = "\(Prefix.id).useHardwareVolumeButtons"
    /// Mirrors the playing group onto the Lock Screen / Control Center Now
    /// Playing card by holding a silent audio session. **On** when unset: it's
    /// the default Lock Screen surface for Cue Super. Read it through
    /// `UserDefaults.lockScreenNowPlayingEnabled`, never `bool(forKey:)`, which
    /// reads unset as off and would leave the default unreachable.
    ///
    /// Being on is not enough to run — `NowPlayingSessionService.isEnabled` also
    /// requires an active subscription, so an unsubscribed user with the default
    /// keeps Live Activities and nothing takes over their audio.
    public static let lockScreenNowPlaying = "\(Prefix.id).lockScreenNowPlaying"
    /// The Plex collections screen's layout (`PlayableListLayout` raw value).
    public static let plexCollectionsLayout = "\(Prefix.id).plexCollectionsLayout"
    /// The layout inside a Plex collection (`PlayableListLayout` raw value).
    public static let plexCollectionLayout = "\(Prefix.id).plexCollectionLayout"
}

public extension UserDefaults {
    /// One accessor, so the unset-means-on default can't be got wrong at a call
    /// site. An explicit `false` — someone who turned it off — still reads false.
    var lockScreenNowPlayingEnabled: Bool {
        get { object(forKey: AppStorageKeys.lockScreenNowPlaying) as? Bool ?? true }
        set { set(newValue, forKey: AppStorageKeys.lockScreenNowPlaying) }
    }

    /// Same shape, same reason — see `AppStorageKeys.useHardwareVolumeButtons`.
    /// The explicit-`false` case matters more here than for the surface itself:
    /// it's how someone who turned this off after their speakers were set to
    /// full volume keeps it off through the update that changed the default.
    var hardwareVolumeButtonsEnabled: Bool {
        get { object(forKey: AppStorageKeys.useHardwareVolumeButtons) as? Bool ?? true }
        set { set(newValue, forKey: AppStorageKeys.useHardwareVolumeButtons) }
    }
}
