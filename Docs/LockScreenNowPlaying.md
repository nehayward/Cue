# Lock Screen Now Playing (iPhone)

How Clic — a controller app that plays no audio of its own — gets onto the
system Now Playing card, and how that card stays current without polling.

```
        Sonos coordinator
              │  WebSocket: metadata + playback
              ▼
   SonosService (.nowPlaying live listener)
              │  live-update observer (.nowPlaying)
              ▼
   NowPlayingSessionService ──► MPNowPlayingInfoCenter   (Lock Screen / CC / CarPlay)
       │                   └──► MPRemoteCommandCenter    (play/pause/skip/scrub)
       │
       ├── silent .playback session (why the card renders at all)
       └── HardwareVolumeService (owner: .session, .absoluteMirror) → group volume
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
  session and deactivate it on teardown, which would drop the claim. That's
  arbitrated by `AudioSessionArbiter`: this service registers a claim, and the
  preview asks the arbiter rather than naming the feature — with no claim
  registered it deactivates exactly as it always did. Interruptions (`.ended`)
  and `mediaServicesWereResetNotification` route to the same recovery.

## Gating

Clic Super. The check lives in `isEnabled` — preference **and** active
subscription — not only on the toggle, because this is a feature that keeps
running with the app closed: a subscription that lapses mid-session has to tear
it down, and a toggle can't do that. `trackCardState` reads `isEnabled`, so the
`@Observable` write when a purchase, restore, or expiry lands re-evaluates on its
own. That also covers cold launch, where `checkSubscription()` hasn't returned
yet and the session simply starts a moment later.

In Preferences the row carries a `SuperBadge` while unsubscribed, and enabling
presents the paywall *without writing the preference* — so the toggle snaps back
by itself and the service never sees a value it would have to undo. Turning it
off always goes through, so a lapsed subscriber isn't stuck with a preference
they can't clear.

## Ownership: not the view layer

`activate()` is called once from `ClicApp.onAppear`; from there the service
watches the model itself with a self-re-arming `withObservationTracking` pass
over the target and `trackCardState` (track identity, artwork URL, duration,
isPlaying, station, available actions — deliberately *not* `playbackPosition`,
which ticks). The preference is read from `UserDefaults` and re-evaluated on
`didChangeNotification`, so the toggle needs no wiring of its own.

The first version hung all of this off a root `ViewModifier`, which is wrong for
a background feature: SwiftUI stops evaluating bodies once the app is
backgrounded, so `onChange` stopped firing exactly when the card was the only UI
left. `@Observable` notifications don't care whether a view is alive.

## Several groups playing at once

iOS has one Now Playing app and one item in it, so only one group can be on the
card. Which one depends on where the user is — the two states want opposite
things, so `resolveTarget()` gives them opposite answers:

| | Rule | Why |
|---|---|---|
| **Foreground** | The selected group wins, even paused | The user is looking at a speaker, and the volume bridge follows the card — the buttons have to control what's on screen |
| **Background** | The playing group wins | The card is all the user can see, so it follows the music |

Fallbacks, in order: selection (foreground only) → first playing group in
`sorted` order → any mirrorable selection. That last one is what keeps a paused
card up when nothing is playing anywhere; without it, pausing from the Lock
Screen would drop the card and leave no way to resume.

`sorted`, not `groups`: `groups` is in Sonos topology-parse order, which is
arbitrary and reshuffles on refresh, so two rooms playing could hand the card
back and forth on an unrelated group change.

## What the card shows

Title is the song (or the station name for an idle radio player, or the room if
even that is missing). The **artist line carries the room**: `The Favors •
Theater`. That line is the only subtitle the Lock Screen card renders — it draws
title and artist and stops — so it's the only place the speaker name can appear.
The album line still carries the real album for the surfaces that do show it
(Control Centre, CarPlay).

## Tapping the card (not implemented — and why the obvious way is a trap)

Tapping the card just foregrounds the app, wherever it was. The card carries no
tap URL and iOS gives no signal that a launch came from it, so there is nothing
to route on.

**Do not route by writing `Router.main.selectedID`.** That was tried: keep the
selection on the mirrored group, and the app is always already on that speaker.
It bricks navigation. The selection is also what the speaker list uses to drive
the split view, so popping back to the list sets it to `nil` — which fires this
service's observation, which writes the id straight back, which pushes the player
again. The user cannot get out of the player to change speakers.

Anything that writes shared navigation state from here has the same shape, since
`resolveTarget()` *reads* the selection: a write feeds its own trigger. **The card
is a mirror. It only reads.**

If routing on launch is wanted, the app already has an opt-in for it —
`AppStorageKeys.speedLaunchNowPlaying` routes `clic://playing` on scene
activation. That fires once per activation rather than on every selection change,
so it can't fight in-app navigation.

## What is actually running while backgrounded

Verified, since the whole design rests on it:

| Running | What it costs |
|---|---|
| The `.nowPlaying` WebSocket (one, on the mirrored group's coordinator) | Idle until the speaker changes something |
| `SonosStreamingService`'s connection refresh | One reconnect per socket every 5 minutes |
| The UPnP ZoneGroupTopology subscription — the FlyingFox listener plus a renewal at 80% of the speaker's ~500 s timeout | Push, not polling: NOTIFY arrives when the topology changes. One renewal request every ~7 minutes |
| `HardwareVolumeService`'s `outputVolume` KVO | Nothing until a volume button or the Lock Screen slider moves |
| `updateTrackInformation` from `liveItemDidChange` | One SOAP fetch per song change — event-driven, not a poll |

**Not running:** `sonosPulse` and `watcher`, the 500–800 ms SOAP loops, both
cancelled in `handleScenePhase(.background)`. They're what would actually cost
battery; everything above is either idle or edge-triggered.

The topology subscription is the one piece that isn't a WebSocket. It predates
this feature and is push-based, so it doesn't change the cost picture — worth
knowing it's there before concluding "only WebSockets are alive".

## Why it doesn't poll

The `.nowPlaying` live listener holds one socket, on the mirrored group's
coordinator, for `[.metadata, .playback]` only. Events write the model in
`SonosService`'s handler and call back through the `.nowPlaying` live-update
observer (keyed by listener, so a second consumer can't silently replace the
first).

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
- **The subscription is addressed by group id, not just coordinator.** Sonos's
  `playback` and `metadata` namespaces are subscribed per group id, and that id
  changes when speakers are grouped or ungrouped even though the coordinator
  stays put. Re-point on any change to coordinator + group id + ip (`run()`'s
  `subscriptionKey`); watching the coordinator alone leaves the socket
  subscribed to a group that no longer exists, and it just goes quiet.
- **Don't drop socket events on the `isEditing` guard.** The guard exists so a
  local play/pause isn't overwritten by the device echoing its pre-command
  state, but it used to skip the whole event, including the item change. These
  events are edge-triggered: drop one and the model stays wrong until something
  else moves it — which, backgrounded, is nothing.
- **Pushed state beats polled state.** Seven things write `Room.isPlaying`: the
  socket, and six SOAP paths (the pulse, `LiveActivityManager`, `getPlaybackInfo`
  sweeps). SOAP is a round trip behind, so a response captured before a pause
  lands after the socket reported it and flips the flag back — invisible on
  screen, where the next poll corrects it, but on the card it reads as playback
  flickering. `Room.markPlaybackState(_:)` stamps pushed writes and
  `hasFreshPlaybackState` makes the polled ones defer for two seconds. With no
  socket connected nothing stamps and the poll behaves as it always did.
- **`PLAYBACK_STATE_BUFFERING` is not a pause.** Sonos reports it while the next
  stream opens, i.e. on every track change. Mapping anything-but-PLAYING to
  `isPlaying = false` left the model stuck on paused for the rest of the song,
  because backgrounded there's no poll to correct it — the card froze after each
  track change. Only PAUSED/IDLE clears the flag; unknown states are left alone.
  `SonosMiniService` skips the same state, for the same reason.

## Favorites

`likeCommand` is a toggle: `isActive` carries the state, each invocation flips
it, and both directions go through `MusicSearchService.isFavorite`/`setFavorite`
— the same per-service dispatch (Apple / Spotify / SoundCloud / Deezer /
Plex-by-rating) the player's heart uses, so the two can't diverge. Looked up once
per song and seeded from `LiveActivityFavoriteStore`, the app-group cache shared
with the Live Activity's like button.

**`LiveActivityFavoriteStore` is what keeps the surfaces in sync**, and both
sides have to participate:

- Writes go through `MusicSearchService.setFavorite`, which records the store.
  `LikeButtonView` used to call the per-service APIs directly, so a like on the
  player screen never reached the card.
- Reads follow the store. The card's `refreshFavorite` only queried the service
  on a *song* change, so it never noticed a like made elsewhere on the current
  song; it now adopts the store's value for the same song, and the observation pass
  reads the store so the write wakes the observation.

`MusicService+Favorite.swift` and `LikeButtonView.swift` are both byte-identical
to the copies on `claude/live-activity-like-button-57o9qu`, so if both land git
merges them without a conflict. Don't "improve" them here — improve them there.

**Where it appears:** surfaces that render feedback commands — CarPlay, some head
units and accessories. The iOS Lock Screen card has no slot for an app-provided
button, so this does not put a heart on the Lock Screen; that surface's path is
the Live Activity's own button. `dislikeCommand` stays disabled — none of these
services take a negative signal.

## Volume

While the session is held the phone's own volume is inaudible, so the hardware
buttons and the Lock Screen slider are re-pointed at the group.
`HardwareVolumeService` runs as `owner: .session` with `configuresAudioSession:
false`: it skips the
`.ambient` reconfiguration that would forfeit the Now Playing claim, and keeps
its `outputVolume` KVO alive while backgrounded — which is exactly when the Lock
Screen slider is used. The service arbitrates ownership itself (`Owner.session` outranks
`Owner.playerScreen`), so the player screen's modifier claims and releases
without knowing what else exists; its `owner` is observed, which is what makes
the modifier take the bridge back when the session ends. The `MPVolumeView` is parked in the key window; its slider only
exists inside a window.

The bridge runs in **absolute** mode here, unlike the player screen's *relative*
mode. Relative reads any change in phone volume as one step up or down on the
group and shoves the system slider back to a midpoint near the ends to keep
headroom — fine for hardware buttons, useless for a Lock Screen slider: its
position means nothing, a drag registers as a single step, and once it pins at 0
or 1 further presses do nothing. Absolute makes the phone's volume *be* the
group's volume, scaled: `syncSystemVolume()` mirrors the group's level onto the
slider (driven from the observation pass, so a change made on the speaker or in the
Sonos app follows), and a user change is sent as a level via `setGroupVolume`.
Sends are coalesced — a drag emits a KVO callback every few pixels and only the
last value matters.

Echo filtering differs by mode for the same reason: relative can compare against
`restorePoint` because its writes always land there, absolute has to remember
`lastWrittenSystemVolume`. One consequence to expect: hardware presses move the
group in ~6-point steps (the system has 16), not the 1-point steps of the player
screen.

## Shape

| Type | Job |
|---|---|
| `NowPlayingSessionService` | Coordinator: gating, which group to mirror, the observation loop, publishing, commands, favorites |
| `SilentAudioSession` | The audio claim — session category, the silence it plays, recovery from interruptions and media-services resets |
| `PlaybackPositionAnchor` (SonosKit) | When to re-state elapsed time and what to state. Pure value type, covered by `PlaybackPositionAnchorTests` |
| `AudioSessionArbiter` | How a song preview hands the session back without knowing the feature exists |

`SilentAudioSession` and `PlaybackPositionAnchor` came out of the service
because neither knows anything about Sonos or the card — one is an audio
lifecycle, the other arithmetic. The anchor lives in SonosKit rather than the
app so it has somewhere to be tested: there is no app-side unit-test target, so
an extraction "for testability" that stayed in the app target would have been
hollow. Its logic caused two visible bugs (the scrubber appearing to stop, and
pausing snapping it to the start of the track); both are now pinned by tests.

## Modern-API and performance notes

Deployment target is **iOS 17**, so nothing here uses an 18+ API.

- **Audio-session activation is off the main actor.** `setActive` is a
  synchronous XPC round trip to mediaserverd — routinely 100 ms, longer when it
  has to interrupt other audio — and `activate()` runs during launch. Only the
  session call is detached; the `AVAudioPlayer` is built on the main actor,
  where it's a cheap in-memory init. `run()` doesn't wait: the socket and the
  volume bridge don't depend on the session, and `publish()` no-ops until
  `isActive`. A generation stamp retires a bring-up that `stop()` beat.
- **Notifications are async sequences**, not block observers with tokens. The
  loop bodies inherit the actor, so there's no `assumeIsolated` to be wrong
  about — which matters, because it traps rather than warns if a notification
  ever arrives off-main. Cancelling the task is the teardown.
- **One observation pass resolves the target once.** `resolveTarget()` scans and
  sorts the groups; doing it once for the decision and again to register the
  reads doubled that on every model change. Resolving *inside* the tracking
  closure gives one pass, and registers exactly the reads that produced the
  answer.
- **Diagnostics use `print`, deliberately.** `os.Logger` would be the modern
  choice and costs nothing in release, but its output needs console filtering to
  see — and this feature is still being brought up on device, where the console
  is the only instrument. Every line is prefixed `🎛 NowPlaying —`; grep that to
  find them all when they come out.
- Also: the silent WAV is a `static let` rather than rebuilt per activation; the
  `UISlider` is resolved once per attach instead of walking `subviews` on every
  read; artwork is held locally rather than read back out of `nowPlayingInfo`
  (whose getter copies the whole dictionary across to MediaRemote); and the
  artwork request matches `ArtworkView`'s cache key and processor so the card
  reuses the image the player screen already decoded.

`HardwareVolumeService.appEvents()` is left as-is — it predates this work, it's
already an `AsyncStream` with correct teardown, and rewriting it would put the
shipped player-screen path at risk for no gain.

## Still deferred

Judged not worth the churn yet, recorded so the next person doesn't rediscover
them:

- **Constructor injection.** Every collaborator is still a singleton reached
  through `.shared`, so the coordinator itself isn't testable.
  `init(sonos:router:subscription:…)` with defaults would fix that without
  touching a call site.
- **The command table.** `registerCommands`, `updateCommandAvailability` and
  `unregisterCommands` each enumerate the commands separately; adding one means
  editing three places.
- **`HardwareVolumeService`'s two modes could be a strategy** rather than a
  `Mode` enum switched in three places — worth it if a third mode appears.
- **Relative volume mode may be obsolete.** Absolute mirroring works for hardware
  buttons too, so deleting `relativeSteps` would remove two algorithms, two echo
  filters and two send paths. Not done because it changes long-standing
  player-screen behaviour (1-point steps vs ~6).

## Removing this feature

After the dependency inversions, no pre-existing type names it. To remove:

1. Delete `NowPlayingSessionService.swift`, `SilentAudioSession.swift`,
   `AudioSessionArbiter.swift`, and `Docs/LockScreenNowPlaying.md`.
2. Delete the `activate()` call in `ClicApp.onAppear`, the preference row and
   its `Binding` in `PreferenceScreen`, the `lockScreenNowPlaying` key, and
   `UIBackgroundModes` from `Info.plist`.
3. In `AudioPlaybackService`, drop the `AudioSessionArbiter.shared.handBack()`
   line (or leave it — with nothing claiming, it returns false and the original
   behaviour stands).
4. Optionally simplify `HardwareVolumeService` back to one owner and one mode.

What stays, because it's independent of the Lock Screen and fixes real
foreground behaviour: the whole `SonosService+LiveListening` registry, the
socket event handlers in `SonosService+SonosEventHandler`, `SuperBadge`, and
`PlaybackPositionAnchor` (a general utility any media surface can use — the
Live Activity has the same interpolation problem).

## Not done yet

- **Watch / CarPlay parity beyond the free ride.** Both surfaces read the info
  center, so they work, but neither has been tested on hardware.
- **A Lock Screen favorite button.** `likeCommand` covers CarPlay and
  accessories, but the Lock Screen card can't host one. That surface's path is
  the Live Activity's button on
  `claude/live-activity-like-button-57o9qu`.
- **Interaction with Live Updates** (`claude/ios-now-playing-notifications-*`).
  That feature's Live Activity and this card are complementary — one is
  push-driven and works away from home, the other is LAN-driven and gives real
  transport controls — but they've never run at the same time. Expect to
  reconcile `UIBackgroundModes` (that branch adds `remote-notification`) and to
  decide whether the card should suppress the Activity when both are on.
