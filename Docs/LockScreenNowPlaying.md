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

## Gating

Clic Super. The check lives in `isEnabled` — preference **and** active
subscription — not only on the toggle, because this is a feature that keeps
running with the app closed: a subscription that lapses mid-session has to tear
it down, and a toggle can't do that. `trackedState()` reads `isEnabled`, so the
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
over `trackedState()` (target group, track identity, artwork URL, duration,
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

The selection follows the card in the background
(`pointSelectionAtMirroredGroup`), which is what keeps card, selection, and
volume bridge on one speaker — and what makes a tap on the card land on the
group it was showing rather than the one that was selected before.

## What the card shows

Title is the song (or the station name for an idle radio player, or the room if
even that is missing). The **artist line carries the room**: `The Favors •
Theater`. That line is the only subtitle the Lock Screen card renders — it draws
title and artist and stops — so it's the only place the speaker name can appear.
The album line still carries the real album for the surfaces that do show it
(Control Centre, CarPlay).

## Tapping the card

The Now Playing card carries no tap URL — iOS simply foregrounds the app, and
gives no signal that the launch came from the card. Intercepting
`didBecomeActive` would therefore route the user to the player on *every* return
to the app (after a phone call, after a share sheet), which is worse than not
doing it.

Instead `pointSelectionAtMirroredGroup` keeps `Router.main.selectedID` on the
group being mirrored, so the app is already on that speaker whenever it opens —
from the card or otherwise. `ClicApp` persists the selection to
`AppStorageKeys.savedGroupID` and restores it at launch, so this survives a cold
start too.

It only fills a selection that isn't already showing something mirrorable:
`resolveTarget()` *prefers* the selection, so overwriting a live one would let
the card drag the user off the speaker they were looking at.

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
- **`PLAYBACK_STATE_BUFFERING` is not a pause.** Sonos reports it while the next
  stream opens, i.e. on every track change. Mapping anything-but-PLAYING to
  `isPlaying = false` left the model stuck on paused for the rest of the song,
  because backgrounded there's no poll to correct it — the card froze after each
  track change. Only PAUSED/IDLE clears the flag; unknown states are left alone.
  `SonosMiniService` skips the same state, for the same reason.

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
- **Favorites.** `likeCommand` was wired and then removed: iOS's Lock Screen card
  has no slot for an app-provided button, so it only surfaced in CarPlay and on
  some accessories — not worth a per-song favorite lookup for. The Lock Screen
  path is the Live Activity's own button
  (`claude/live-activity-like-button-57o9qu`, which also extracts the shared
  per-service favorite API). Revisit if CarPlay becomes a target.
- **Interaction with Live Updates** (`claude/ios-now-playing-notifications-*`).
  That feature's Live Activity and this card are complementary — one is
  push-driven and works away from home, the other is LAN-driven and gives real
  transport controls — but they've never run at the same time. Expect to
  reconcile `UIBackgroundModes` (that branch adds `remote-notification`) and to
  decide whether the card should suppress the Activity when both are on.
