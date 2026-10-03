# Sonos Separation

Cue has to be a complete player with no speaker on the network, with Sonos as
an optional layer on top (see Product Priorities in `CLAUDE.md`). This is the
plan for getting there, what has landed, and what is left.

One item per branch. Branch names follow `claude/<slug>`; each item names the
files it touches and what "done" looks like, so a branch can be opened from
this file alone. Tick the box when the branch lands.

## Where things stand

Measured at the start of this work:

- **No playback layer between views and Sonos.** Views check whether a speaker
  is selected (`route.group`) and then call `SonosService` directly. 193 of the
  app's 270 Swift files import SonosKit; 112 reference `SonosService`. The
  heaviest are `CueApp.swift`, `LargePlayerView.swift`,
  `Mac/DockMenuCoordinator.swift`, `SpeakerListScreen.swift`,
  `SpeakerSettingsView.swift`, `Queue/QueueScreen.swift`,
  `ContainerLargePlayerView.swift`, `Search/ArtistDetailView.swift` and
  `SelectGroupView.swift`.
- **Shared music code lives in SonosKit.** `PlayableContent`, `MusicService`,
  `QueuePosition`, `MusicSearchService` and the Plex, Subsonic, Files, TuneIn
  and Apple Music browse services are all in `Packages/SonosKit`. SonosKit
  depends on MusicSearchKit and Defaults; MusicSearchKit does not depend on
  SonosKit. VibesDS depends on SonosKit through five files
  (`SceneButton`, `LiveActivityButtonStyle`, `Components/VibeContentArtwork`,
  `SceneView`, `SceneListView`). SonosKitMini keeps its own copies of
  `PlayableContent` and `MusicService`.
- **The other surfaces only work with Sonos.** Widgets (38 of 53 files import
  SonosKit), `Widgets/Intents/*`, the Live Activity (`LiveActivityManager`
  stops when there are no groups), Watch, TV, Cue Mini, the Mac Dock menu and
  the share extension. App Shortcuts (`Cue/CueAppShortcutProvider.swift`) are
  commented out entirely.

## Phase 1 — Works without Sonos (done, PR #1)

- [x] **Sonos is opt-in.** `SonosService.isEnabled` blocks `monitor()` and every
  group load, so nothing searches the network and the Local Network prompt
  never appears while it is off. Read at launch in `AppDelegate`
  (`loadEnabledPreference()`); a new install is off, an install that knows a
  household is on. Widgets, TV, Watch and Cue Mini never read it and stay on.
- [x] **Turned on from** onboarding (`SonosQuestionStep`), Settings ▸ Sonos ▸
  Use Sonos Speakers, or Find Sonos Speakers in the Play On menu.
- [x] **Speaker-only UI hidden while off:** the rest of the Sonos settings,
  Scenes, the Lock Screen section, Quick Launch, Cue Mini, Sonos playlists.
- [x] **No dead-end speaker picker:** content the device can't play shows an
  alert instead (`PlayDestinationRouter.askForSpeaker`).
- [x] **Artist and song radio on the device** through Apple Music stations
  (`MusicSearchService.appleStation(for:)`,
  `PlayDestinationRouter.playRadio(from:onGroup:)`).
- [x] **Onboarding shows again** and asks "Do you have Sonos?". The paywall and
  newsletter steps are held back; `advanceToPostServices()` in
  `Cue/Onboard/WelcomeScreen.swift` is where to bring them back.
- [x] **Clic leftovers removed** from Cue's text files.

## Phase 1 — Left over

- [ ] **Remove dead code** — `claude/remove-dead-code`
  Deliberately skipped in Phase 1.
  - `Cue/OldCueApp.swift` (1,234 lines, all commented out).
  - The commented-out launch block in `Cue/CueApp.swift` (search for
    `//                SonosService.shared.groupsChanged`). Check first
    whether anything in it still needs a live home, e.g. the
    `groupsChanged` → Live Activity wiring and `subscriptionUpdated`.
  - Steps 2–4 of `Ideas/device-first-services.md`: the Spotify, Tidal,
    Deezer, SoundCloud, Pandora, Sonos Radio and speaker Music Library code.
    It is already hidden by `MediaSearchService.supported`, but
    `BrowseScreen.swift` still switches to those screens.
  Done when: the files are gone, every scheme builds, and nothing that was
  reachable before is lost.

- [ ] **Replace the old icon everywhere else** — `claude/extension-icons`
  The main app, Mac and Watch use `Cue/Icon.icon`. The share extensions
  (CueAction "Listen with Cue", QueueAction), Widgets and Vision still use
  `AppIcon.appiconset`, which is the old Clic bars artwork, as are
  `AppIconDark.appiconset` and `MacAppIcon.appiconset`.
  `CueIconGlass.imageset` is a render of `Icon.icon` for in-app use; re-render
  it if the icon changes.
  Done when: no target ships the bars artwork.

- [ ] **Release notes for Beta 1** — `claude/beta1-release-notes`
  `ReleaseNotes.md` and `Changelog.md` carry 63 versions of Clic's history
  (back to 2023). Start a "Cue Beta 1" section and move the old history to
  an archive file.

- [ ] **Sonos Radio "not working"** — reported, not yet looked into. First find
  out which: the Sonos logo (`Image("Sonos Radio", bundle:
  .musicSearchKitBundle)`) missing on the onboarding Sonos question, or Sonos
  Radio as a service. Sonos Radio is on the device-first exclusion list, so
  the service itself is expected to be hidden.

- [ ] **Radio for Plex and Subsonic on the device** — `claude/device-radio-self-hosted`
  Artist and song radio on the device is Apple Music only. Subsonic can build
  a queue from `getSimilarSongs2` / `getTopSongs` (`SubsonicAPI.swift`); Plex
  has artist radio through its station hubs. Both would play as an ordinary
  queue, not a live station.
  Done when: Play Radio on a Plex or Subsonic artist plays on the device with
  no speaker.

- [ ] **Test Phase 1 on hardware.** Fresh install, answer No: no Local
  Network prompt anywhere, no Sonos settings apart from the switch. Answer
  Yes: the prompt appears on the discovery page and speakers are found.
  Artist and song radio play on the device. Turning Sonos off while playing
  on a speaker moves back to the device.

## Phase 2 — One playback layer

- [x] **`PlaybackController` protocol** — `claude/modest-gates-wgmawc`
  `Cue/Services/PlaybackController.swift`: now-playing state, transport,
  seek and scrubbing, shuffle and repeat, the queue gauge and the sleep
  timer, in seconds on both sides. `LocalPlaybackService` conforms (most of
  it was its API already); `SonosGroupController` wraps one group by
  coordinator id. `PlaybackRoute.controller` is the route's,
  `PlaybackRoute.presented` the one on screen (see below). Not in it yet:
  queue editing (add, move, remove) and volume — the panel and the volume
  row still have a view per backend.

- [ ] **Move the player screens onto it** — `claude/player-on-controller`
  Done for `Views/PlayerView.swift`, the mini player (`MusicPlaybackView` in
  `CueApp.swift`) and the choice in `Views/QueueNextUpView.swift`: one set
  of views reads `presented`, and a switch no longer rebuilds the player
  (`PlayerSessionModifier` had put the whole screen in one of two `if`
  branches, which rebuilt it, state and all, on every switch).
  **The hand-off hold**: while a switch carries a queue across,
  `presented` stays on the source until the target is playing the same
  song with its cover in the player's cache entry (`PlaybackRoute.hold`,
  `releaseHold(whenShowing:on:)`), so the player carries on with the song
  instead of showing the speaker's last track, then jumping. The transport
  rests meanwhile, the bar runs on from the switch, and the route label
  reads "Moving to …". Capped at 12 s.
  Left: `LargePlayerView.swift` / `ContainerLargePlayerView.swift` (the
  speaker-list player), `Queue/QueueScreen.swift`, the two queue panels
  (`LocalNextUpView` / `GroupNextUpView`), `VolumeMultiControlView`,
  `VolumeControlsScreen`, `HardwareVolumeService`, and volume and queue
  editing on the protocol so the volume row and the panel can be one view.
  Speaker-only extras (grouping, sleep timer on the speaker, EQ) stay
  behind `controller.group`.
  Done when: none of these files branch on `route.group` for transport,
  queue or volume.

- [ ] **One play call** — `claude/route-play`
  Every Play button passes a `(GroupRoom, QueuePosition)` closure that calls
  `sonosService.queue…`. Replace with `PlaybackRoute.play(_:position:)`,
  which picks the controller. Start with Search, Library and Playlist.
  Done when: no view builds a Sonos queue closure to play something.

## Phase 3 — Split the packages

- [ ] **`CueCore` package** — `claude/cuecore-package`
  Move `PlayableContent` (minus the Sonos DIDL / `URIMetadata` code, which
  becomes a SonosKit extension), `MusicService`, `QueuePosition`,
  `MusicSearchService` and the Plex, Subsonic, Files, TuneIn and Apple Music
  browse services out of SonosKit. SonosKit then depends on CueCore, not the
  other way round.
  Done when: `import SonosKit` is not needed to search, browse or play on the
  device.

- [ ] **VibesDS without SonosKit** — `claude/vibesds-no-sonos`
  Move `SceneButton`, `LiveActivityButtonStyle`, `SceneView`, `SceneListView`
  into the app, and point `VibeContentArtwork` at CueCore.

- [ ] **Fence the Sonos code** — `claude/sonos-folder`
  Speaker screens move under `Cue/Sonos/`; `import SonosKit` only appears
  there and in `SonosGroupController`.

## Phase 4 — The other surfaces

Also Tier 3 of `Ideas/device-player-roadmap.md`. Each one moves onto the
Phase 2 controller so it works for the device as well as a speaker.

- [ ] **Widgets and intents** — `claude/widgets-device`
- [ ] **App Shortcuts** (uncomment and rebuild `CueAppShortcutProvider.swift`) — `claude/app-shortcuts`
- [ ] **Live Activity for the device** — `claude/device-live-activity`
- [ ] **Watch** — `claude/watch-device`
- [ ] **TV** — `claude/tv-device`
- [ ] **Cue Mini** — `claude/cuemini-device`
- [ ] **Mac Dock menu and menu commands** (`Mac/DockMenuCoordinator.swift`,
  `PlaybackTransportControls` in `CueApp.swift`) — `claude/mac-menus-device`
- [ ] **Share extension** (`PlayAction/`) — `claude/share-extension-device`
