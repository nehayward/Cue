# Lock Screen Now Playing (iPhone)

How Clic — a controller app that plays no audio of its own — gets onto the
system Now Playing card, and how that card stays current without polling.

```
        Sonos coordinator
              │  WebSocket: metadata + playback
              ▼
   SonosService (.nowPlaying live listener)
              │  onLiveUpdate(group)
              ▼
   NowPlayingSessionService ──► MPNowPlayingInfoCenter   (Lock Screen / CC / CarPlay)
       │                   └──► MPRemoteCommandCenter    (play/pause/skip/scrub)
       │
       ├── silent .playback session (why the card renders at all)
       └── HardwareVolumeService (ownsAudioSession: false) → group volume
```

## The silent-audio requirement

iOS renders the Now Playing card only for the app that owns audio output.
Setting `MPNowPlayingInfoCenter.nowPlayingInfo` from an app with no active audio
session does nothing — that's the finding recorded in `NOW_PLAYING_NOTES.md`,
and why the Live Updates feature had to use a Live Activity for its Lock Screen
surface instead.

`NowPlayingSessionService` works around it the way every third-party Sonos
controller does: activate `.playback` and loop a silent buffer, so the system
treats Clic as the playing app while the audible output comes from the speakers.

Non-negotiables learned the hard way:

- **No category options.** `.mixWithOthers` and `.duckOthers` both let other
  audio keep the Now Playing claim, which loses the card. It follows that
  holding the session *does* interrupt podcasts/music on the phone — accepted,
  and why the feature is opt-in and dropped the moment the target speaker is
  idle.
- **`UIBackgroundModes: audio`** is required, both to keep the card's controls
  alive and to keep the WebSocket delivering: `handleScenePhase(.background)`
  cancels the SOAP pulse.
- **The session is borrowable.** Song previews (`AudioPlaybackService`) take the
  session and deactivate it on teardown, which would drop the claim — teardown
  calls `reclaimSession()` instead, which also restores the category the preview
  left behind. Same for interruptions (`.ended`) and
  `mediaServicesWereResetNotification`.

## Why it doesn't poll

The `.nowPlaying` live listener holds one socket, on the mirrored group's
coordinator, for `[.metadata, .playback]` only. Events write the model in
`SonosService`'s handler and call back through `onLiveUpdate`.

Elapsed time is never pushed on a timer. The info center interpolates from the
`elapsedPlaybackTime` + `playbackRate` anchor, so `publish()` re-anchors only
when the card's content changed or the speaker's position drifted more than 2 s
from what the system is already showing (a seek, or a skip from another
controller). Steady-state cost of a playing song: one publish at the track
change, and nothing until the next one.

## Listener-keyed sockets

The card follows the *playing* group; the player screen shows the *visible*
one. They're often the same, but not always — so subscriptions are keyed by
`LiveListener` (`.viewing`, `.nowPlaying`) and `reconcileLiveConnections()`
connects the union. Notes for anyone extending this:

- `SonosStreamingService.addPlayer` silently skips a player it already holds, so
  widening a socket's event set requires remove-then-add. Reconcile does this.
- Never call `disconnectAll()` to re-point a subscription (`LargePlayerView`
  used to) — it takes every listener's socket with it.

## Favorites

`likeCommand` is registered as a toggle: `isActive` carries the current state,
each invocation flips it, and both directions go through
`MusicSearchService.isFavorite`/`setFavorite` — the same per-service dispatch
(Apple / Spotify / SoundCloud / Deezer / Plex-by-rating) the player's heart uses,
so the two can't diverge. State is looked up once per song and seeded instantly
from `LiveActivityFavoriteStore`, the app-group cache shared with the Live
Activity's like button.

**Where it actually shows up:** feedback commands are surfaced by CarPlay and
some head units and accessories. iOS's own Lock Screen / Control Center card has
no slot for a custom button — it renders artwork, text, scrubber, transport,
volume, and the route picker, and nothing else. So this does *not* put a heart on
the Lock Screen; the Lock Screen path for that is the Live Activity
(`claude/live-activity-like-button-57o9qu`), which owns its own button.

`dislikeCommand` stays disabled — none of these services take a negative signal.

## Volume

While the session is held the phone's own volume is inaudible, so the hardware
buttons and the Lock Screen slider are re-pointed at the group.
`HardwareVolumeService` runs in `ownsAudioSession: false` mode: it skips the
`.ambient` reconfiguration that would forfeit the Now Playing claim, and keeps
its `outputVolume` KVO alive while backgrounded — which is exactly when the Lock
Screen slider is used. `HardwareVolumeControlModifier` stands down while the
session owns the bridge and takes it back when the session ends (it observes
`isActive`). The `MPVolumeView` is parked in the key window; its slider only
exists inside a window.

## Not done yet

- **Watch / CarPlay parity beyond the free ride.** Both surfaces read the info
  center, so they work, but neither has been tested on hardware.
- **Point `LikeButtonView` / `FavoriteMenuButton` at
  `MusicSearchService.setFavorite`.** They still hold their own copies of the
  per-service switch, so a favorite made in the app doesn't populate
  `LiveActivityFavoriteStore` (the card and the activity then pay for a lookup
  that was already done). `claude/live-activity-like-button-57o9qu` does exactly
  this refactor — it's deliberately left to that branch rather than done twice.
- **Interaction with Live Updates** (`claude/ios-now-playing-notifications-*`).
  That feature's Live Activity and this card are complementary — one is
  push-driven and works away from home, the other is LAN-driven and gives real
  transport controls — but they've never run at the same time. Expect to
  reconcile `UIBackgroundModes` (that branch adds `remote-notification`) and to
  decide whether the card should suppress the Activity when both are on.
