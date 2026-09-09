# Device Player Roadmap

What the on-device player (`LocalPlaybackService`, the "This Device" route)
still needs to stand next to Apple Music and Plexamp. Today it plays Apple
Music, Plex, Subsonic, TuneIn and Apple stations, and a Files folder, with
route hand-off to Sonos, a rolling offline cache, downloads, a queue that
survives relaunch, a lossless readout, and a sleep timer. The list below is
what a Plexamp or Navidrome user tests in their first ten minutes and does
not find.

One item per branch. Branch names follow `claude/<slug>`; each item names
the files it touches and what "done" looks like, so a branch can be opened
from this file alone. Tick the box and add the release-notes line when the
branch lands.

## Tier 1 — table stakes

- [ ] **Local queue reorder and remove** — `claude/local-queue-edit`
  The Sonos queue drags and swipes; the device queue in
  `Cue/Views/QueueNextUpView.swift` is tap-to-jump only.
  Files: `QueueNextUpView.swift`, `Cue/Views/QueuePanel.swift`,
  `LocalPlaybackService` (add `move(from:to:)`, `remove(at:)`, re-arm the
  run when the edit crosses `currentIndex`).
  Done when: drag to reorder and swipe to remove work in the panel and the
  full player, the armed run follows the edit without a gap, and the saved
  queue on disk reflects it.

- [ ] **Sticky shuffle mode** — `claude/local-shuffle-mode`
  `shuffleUpNext()` is a one-shot reshuffle of the tail. Users expect a
  toggle that stays on, applies to the next album or playlist queued, and
  restores the original order when turned off.
  Files: `LocalPlaybackService` (keep the unshuffled order alongside
  `queue`, persist the flag in `LocalQueueStore`), `Cue/Views/PlayerView.swift`
  shuffle button, `enqueue(_:at:shuffle:)`.
  Done when: shuffle survives relaunch and route hand-off to Sonos, and
  unshuffle puts the current song back at its original index.

- [ ] **Report plays to Plex and Subsonic** — `claude/server-play-reporting`
  Nothing calls Subsonic `scrobble` or Plex `:/timeline`, so server play
  counts, "recently played", and Navidrome's Last.fm / ListenBrainz
  forwarding never fire from Cue.
  Files: `Packages/MusicSearchKit/.../SubsonicAPI.swift` (`scrobble` with
  `submission=false` at start and `true` past the half-way or 4-minute
  mark), `PlexAPI.swift` (`/:/timeline` with `state`, `time`, `duration`
  every ~10 s and on stop), a hook in `LocalPlaybackService`'s poll loop.
  Done when: playing a song in Cue bumps its play count on the server and
  a Navidrome server forwards it to Last.fm.

- [ ] **Streaming quality tiers** — `claude/stream-quality-settings`
  Plex and Subsonic stream the raw file, so a FLAC library burns cellular
  data. Add Wi-Fi and cellular quality settings.
  Files: `SubsonicAPI.streamURL` (`maxBitRate`, `format`), `PlexAPI`
  (transcode decision `/music/:/transcode/universal/decision` or direct
  play), `PlaybackCache` (cache the tier actually fetched), a Quality
  section in `Cue/Preferences/PreferenceScreen.swift`, keys in
  `Packages/Defaults`.
  Done when: Original / High / Data Saver per network, the audio-quality
  readout shows what is actually playing, and the cache does not serve a
  data-saver copy on Wi-Fi.

- [ ] **CarPlay** — `claude/carplay`
  No CarPlay scene exists; `Cue/Services/AudioOutputRoute.swift` only
  detects the route. Needs the CarPlay audio entitlement.
  Files: new `Cue/CarPlay/` with a `CPTemplateApplicationSceneDelegate`,
  list templates for Recents, Playlists, Albums, Radio, Downloads, and the
  Now Playing template bound to `LocalPlaybackService`; scene manifest in
  `Cue/Info.plist`.
  Done when: browsing and playback work in the CarPlay simulator with the
  device route, and Sonos groups appear as a "Play on" list.

- [ ] **Siri and App Shortcuts for the device** — `claude/local-app-intents`
  `Cue/CueAppShortcutProvider.swift` is fully commented out and every
  intent in `Widgets/Intents/` targets a Sonos device.
  Files: new intents `PlayLocalIntent` (search phrase or entity),
  `LocalPlaybackIntent` (play / pause / next / previous), an
  `AppShortcutsProvider` with phrases, entity queries for playlists and
  albums per provider.
  Done when: "Play <playlist> in Cue" starts the device route from Siri and
  the intents show up in Shortcuts.

- [ ] **AirPlay route picker** — `claude/airplay-picker`
  `PlaybackRouteButton` picks device vs Sonos group only; there is no
  `AVRoutePickerView`, so the phone cannot bridge to HomePods or AirPlay
  speakers.
  Files: `Cue/Views/PlaybackRouteButton.swift` (an AirPlay row under the
  device), `LocalPlaybackService` (`allowsExternalPlayback`, audio session
  category check), `AudioOutputRoute.swift`.
  Done when: the picker appears in the route menu, playback moves to a
  HomePod, and the mini player shows the AirPlay destination name.

## Tier 2 — differentiators for self-hosters

- [ ] **Lyrics** — `claude/lyrics`
  OpenSubsonic returns synced LRC (`getLyricsBySongId`), Plex exposes
  lyric streams, and Files can read embedded USLT or a sidecar `.lrc`.
  Files: `SubsonicAPI`, `PlexAPI`, `FilesLibraryService`, a `LyricsService`
  with a common `[TimedLine]` model, a lyrics page in `PlayerView.swift`
  that follows `progress`.
  Done when: synced lyrics scroll with the song on all three providers,
  plain lyrics show when no timing exists, and the tab is hidden when
  there are none.

- [ ] **Audio engine for the stream backend** — `claude/audio-engine`
  Move Plex, Subsonic, and Files off `AVQueuePlayer` onto `AVAudioEngine`.
  One investment unlocks EQ, ReplayGain, crossfade, playback speed, and
  gapless across service boundaries. Apple Music stays in
  `ApplicationMusicPlayer`.
  Files: new `Cue/Services/Audio/` (scheduler, `AVAudioUnitEQ`,
  `AVAudioUnitTimePitch`, gain node), `LocalPlaybackService.armStream`
  swap, `LocalNowPlayingPresenter` rate reporting.
  Done when: the existing stream tests pass, the cache hot-swap still
  works, and background playback and interruptions behave as before.
  Split the features below out as follow-up branches once this lands:
  - [ ] **EQ presets and a 10-band graphic EQ** — `claude/eq`
  - [ ] **ReplayGain / volume normalization** — `claude/replaygain`
    (Subsonic `replayGain` fields, Plex `gain` on the stream, tags in Files;
    also evens out Apple vs Plex loudness in one queue)
  - [ ] **Crossfade for the device route** — `claude/local-crossfade`
    (the Sonos setting already exists; mirror it)
  - [ ] **Playback speed** — `claude/playback-speed`

- [ ] **Autoplay and similar songs** — `claude/local-autoplay`
  When the queue ends, continue with Subsonic `getSimilarSongs2` or Plex
  track radio (`/library/metadata/{id}/station`). This is the Plex and
  Subsonic half that `auto-dj.md` skips.
  Files: `LocalPlaybackService` (queue-low hook at ~3 tracks left),
  `SubsonicAPI`, `PlexAPI`, an Autoplay toggle in `PreferenceScreen`.
  Done when: a five-song album keeps playing related songs with the toggle
  on and stops cleanly with it off.

- [ ] **Instant mixes and smart lists** — `claude/smart-lists`
  Artist and genre mixes, Most Played, Never Played, Recently Added, On
  This Day, and a "for you" row on Home. Depends on the timestamped play
  log in `listening-stats.md` for the history-driven lists.
  Files: `Cue/Tabs/ProviderCollection.swift` (new collection kinds),
  `PlexLibraryLists.swift`, `SubsonicLibraryLists.swift`,
  `LocalLibraryLists.swift`, `HomeScreen.swift`.
  Done when: each list plays as a container with Play Next / Play Last and
  respects the provider that owns it.

- [ ] **Radio polish** — split per `radio-local-stations.md`
  - [ ] **Station favorites for TuneIn** — `claude/radio-favorites`
    (`MusicService.supportsFavoriteTrack` excludes tuneIn; store locally,
    add a Favorites row to `RadioScreen`)
  - [ ] **Pasted stream URLs** — `claude/radio-stream-url`
    (device side first, Sonos via `x-rincon-mp3radio://` per the doc)
  - [ ] **Radio Browser as a source** — `claude/radio-browser`
  - [ ] **Location-accurate local radio** — `claude/radio-location`
  - [ ] **Recently played stations row** — `claude/radio-recents`

- [ ] **Subsonic multi-server** — `claude/subsonic-multi-server`
  `SubsonicAPI` stores one server, username, and keychain password.
  Follow Plex's server picker pattern (`Cue/Authorization/PlexConnectionPicker.swift`).
  Done when: two Navidrome servers coexist, each with its own library
  cache and downloads, and the active one is switchable from Services.

- [ ] **Jellyfin and Emby provider** — `claude/jellyfin`
  The checklist at the end of `Docs/AddingMusicService.md` via
  `DirectStreamProvider`.
  Done when: browse, search, playlists, favorites, and downloads match the
  Subsonic feature set on both the device and Sonos routes.

## Tier 3 — presence on the other surfaces

The device player has no widgets, Live Activity, Apple Watch, Apple TV, Cue
Mini, or visionOS presence. Everything in `Widgets/`, `Watch/`, `TV/`, and
`CueMini/` is keyed to a Sonos device.

- [ ] **Live Activity for device playback** — `claude/local-live-activity`
  (`Widgets/LiveActivity/`, `Cue/LiveActivityManager.swift`; mirror the
  Sonos card with the device as the "room")
- [ ] **Now Playing widget and control widget for the device** —
  `claude/local-widgets` (`Widgets/NowPlayingWidget/`, `Widgets/ControlWidgets/PlaybackControlWidget.swift`)
- [ ] **Apple Watch remote for the phone's playback** — `claude/watch-local-remote`
  (`Watch/`, WatchConnectivity to `LocalPlaybackService`)
- [ ] **Cue Mini shows device playback** — `claude/mini-local-playback`
  (`CueMini/`, the menu bar card follows `PlaybackRoute`)
- [ ] **Apple TV device player** — `claude/tv-local-playback`
  (`TV/TVPlayerView.swift`; Plex and Subsonic stream on the TV itself)

## Smaller wins

Pair these with a related branch above rather than opening their own.

- [ ] **Sleep-timer fade-out** — with `claude/audio-engine` or as a volume
  ramp on `streamVolume` today
- [ ] **Offline mode toggle** — filter the library to downloads and the
  playback cache when there is no network (`DownloadManager`,
  `PlaybackCache`, `PlayableListView.swift`)
- [ ] **Go to album / artist from the device player** — `PlayerView.swift`
  ellipsis menu
- [ ] **Release notes for the Files provider, Downloads, and the playback
  cache** — none of the three is in `ReleaseNotes.md` or `Changelog.md`
  yet

## Suggested first bundle

Queue editing, sticky shuffle, server play reporting, and quality tiers.
Each is small, touches code that already exists, and together they fix
what a Plexamp or Navidrome user checks first.
