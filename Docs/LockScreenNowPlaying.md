# Lock Screen Now Playing (iPhone)

How Cue — a controller app that plays no audio of its own — gets onto the
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
                    ↑ only with "Use iPhone Volume Buttons" on, and only on
                      the phone's own speaker — see "Where the phone is"
```

## The silent-audio requirement

iOS renders the Now Playing card only for the app that owns audio output.
Setting `MPNowPlayingInfoCenter.nowPlayingInfo` from an app with no active audio
session does nothing — that's the finding recorded in `NOW_PLAYING_NOTES.md`,
and why the Live Updates feature had to use a Live Activity for its Lock Screen
surface instead.

`NowPlayingSessionService` works around it the way every third-party Sonos
controller does: activate `.playback` and loop a silent buffer, so the system
treats Cue as the playing app while the audible output comes from the speakers.

Non-negotiables learned the hard way:

- **No category options.** `.mixWithOthers` and `.duckOthers` both let other
  audio keep the Now Playing claim, which loses the card. So holding the session
  *does* stop whatever the device itself is playing.
- **Which is why it isn't taken until the speaker is playing.** This used to be
  claimed for any mirrorable target, including a paused speaker the user merely
  had selected — so opening Cue killed a podcast to show a card for something
  that wasn't playing. `run()` now calls `beginSessionIfNeeded()` only when the
  target is playing (or the session is already held, so a pause doesn't hand the
  audio back and forth; releasing is the idle window's job). The volume bridge
  waits on the same condition: mirroring the group's level onto the device's
  volume is harmless while that volume is inaudible, and drags the user's podcast
  to the Sonos group's level when it isn't.
- **`UIBackgroundModes: audio`** is required, both to keep the card's controls
  alive and to keep the WebSocket delivering: `handleScenePhase(.background)`
  cancels the SOAP pulse.
- **The loop has to pause when the speaker pauses.** iOS derives the card's
  transport state from the audio session, not from `MPNowPlayingInfoCenter`
  alone. An app whose session is actively rendering audio *is* playing as far as
  the system is concerned, so a loop that never pauses pins the card to playing
  and discards every `rate = 0` / `playbackState = .paused` we publish — the
  symptom being a correct-looking log (`state=2 rate=0.0`) with a card that
  never changes. `SilentAudioSession.setPlaying(_:)` mirrors the speaker onto
  the loop, and `publish()` calls it *before* the info-centre write so the two
  agree by the time the system reads them.
- **Pause, never deactivate.** A paused player on a live session is the state a
  music app sits in when the user pauses it, and the card stays ours.
  Deactivating hands it away — that's `stop()`, and it's a different operation.
- **The session is borrowable.** Song previews (`AudioPlaybackService`) take the
  session and deactivate it on teardown, which would drop the claim. That's
  arbitrated by `AudioSessionArbiter`: this service registers a claim, and the
  preview asks the arbiter rather than naming the feature — with no claim
  registered it deactivates exactly as it always did. Interruptions (`.ended`)
  and `mediaServicesWereResetNotification` route to the same recovery.
- **A route change isn't an interruption.** Unplugging headphones or losing a
  Bluetooth route stops the player on `.oldDeviceUnavailable` and posts no
  interruption, so the claim went silently — and since a stopped loop now means a
  paused card, visibly wrong. `routeChangeNotification` reclaims too.

None of this reaches the speakers. A call, Siri, an alarm or another app can take
the *card* away and Sonos keeps playing throughout; the loop exists only to hold
the claim, and every recovery path above is about getting the claim back.

## Gating

Cue Super. The check lives in `isEnabled` — preference **and** active
subscription — not only on the toggle, because this is a feature that keeps
running with the app closed: a subscription that lapses mid-session has to tear
it down, and a toggle can't do that. `trackCardState` reads `isEnabled`, so the
`@Observable` write when a purchase, restore, or expiry lands re-evaluates on its
own. That also covers cold launch, where `checkSubscription()` hasn't returned
yet and the session simply starts a moment later.

In Preferences the **whole row** is `.disabled` while unsubscribed, and a clear
overlay opens the paywall on tap — the overlay sits outside the `.disabled` so it
still takes the tap, which a disabled row can't. The `SuperBadge` is on the
**section header**, not the row: every option in the section needs Super, so
marking the section says what marking one row only implied. It moved there when
the picker's row lost its title (see "Live Activities" below) and had nothing left
to hang a badge on.

Gating the *row* rather than the Now Playing segment took a wrong turn first.
`.segmented` renders each label through `UISegmentedControl`, which takes the
label's plain string: an SF Symbol interpolated into the segment's `Text` is
dropped on the way, and there is no way to grey one segment — `.disabled` is
all-or-nothing. That looked like a reason to leave the picker enabled and gate
the write instead. It wasn't: **every** option here needs Super, because
`CueApp` guards `createActivity` on the subscription too, so a non-subscriber
gets no Live Activity either. There was never anything to leave enabled.

The write path keeps its own guard anyway — selecting Now Playing without a
subscription presents the paywall and writes nothing, so the picker snaps back
and the service never sees a value it would have to undo. Unreachable while the
row is disabled, and worth keeping: it's the invariant stated where the write
happens.

### The preference defaults to on

`lockScreenNowPlaying` is **on when unset** (`UserDefaults
.lockScreenNowPlayingEnabled` — never `bool(forKey:)`, which reads unset as off
and would make the default unreachable). Now Playing is the Lock Screen surface
Super is meant to give you, so a subscriber shouldn't have to go and find it.

Two consequences to hold together:

- **It doesn't leak to non-subscribers.** `isEnabled` is preference **and**
  subscription, so nothing takes over their audio and `reconcileLiveActivities()`
  (which reads the same thing) doesn't fire. Not that they'd notice the second
  part — `CueApp` guards `createActivity` on the subscription, so they have no
  Live Activities to suspend.
- **The picker shows the stored preference, greyed.** No subscription check in
  `lockScreenSurface`: with the whole row disabled there's no half-usable state
  to describe, and what it shows while greyed is an honest preview of what a
  subscriber gets. Buying Super needs no second step, since the preference was
  already on — and a subscriber who explicitly chose Live Activity has `false`
  stored, so the default never reaches them.

## Live Activities

Both features draw a Sonos group on the Lock Screen, so they don't both run.
`reconcileLiveActivities()` (called at the top of `evaluate()`) turns Live
Activities off while Lock Screen Controls is on.

In Preferences the two are **one segmented control** — `Live Activity | Now
Playing | Off` — at the top of a **Lock Screen** section. They were a pair of
switches that moved each other, which from the outside is indistinguishable from
a bug; a picker says "pick one" on its face and the footnote under it describes
whichever is selected. **The picker's row has no title of its own** — it read
"Lock Screen" directly beneath a section header reading "Lock Screen", and the
segments already name the three choices, so it was the one line in the section
carrying no information. The selection is derived from the two booleans
(`lockScreenSurface`) rather than stored — a third copy would be one more thing
to keep in step.

The section is the old **Live Activities** section, renamed: it can't be called
that once it holds the choice *between* surfaces. Compact Live Activities and
Volume Steps stayed put under the picker, and *Use iPhone Volume Buttons* later
joined them from the Playback section — see "Where the phone is". Reading order
is Now Playing's row first, then the two Live Activity ones.

**Each row is present only for the surface it configures.** They were dimmed in
place at first, on the theory that a section which doesn't resize is easier to
follow and the picker directly above explains the greying. In practice a list of
permanently disabled controls reads as broken, and once there was a row for
*each* surface the two sets had nothing in common to keep aligned — whichever
segment you were on, most of the section was dead. The section now shows what the
current choice can be configured with and nothing else.

Insertion and removal are animated from `lockScreenSurfaceBinding`'s setter
rather than by an `.animation` on the section, so the transition covers the one
change the user made. A defaults write from somewhere else — another window, the
service reconciling Live Activities — shouldn't slide rows around under them. The
paywall path sits outside the `withAnimation` because it writes nothing: the
picker snaps back and there are no rows to move.

`liveActivitiesSuspendedByLockScreen` records that *this* is what turned them
off, so moving the picker off **Now Playing** restores them. Without it the user
lands on **Off** having never chosen it.

**The restore is gated on the preference, not on `isEnabled`.** `isEnabled` is
also false for the moment at launch before `checkSubscription()` returns, and
restoring there flipped Live Activities on for someone whose setting says Now
Playing — the app then created an activity, and the next pass, which flips the
flag back, raced the creation. Reported from the beta as "the Now Playing screen
disappeared and I see something like a Live Activity, but preferences say Now
Playing." A lapsed subscription needs no restore either: nothing starts a Live
Activity without one.

Two details that aren't obvious:

- **The keys live in the app-group suite, not `AppStorageKeys`.** The widget
  intents (`CreateLiveActivityIntent`, `PlaybackIntent`, …) start activities from
  the extension's process, where `UserDefaults.standard` is a different
  container — an app-local switch would have been invisible to exactly the call
  sites that bypass the app. Read through `UserDefaults.liveActivitiesEnabled`,
  never `bool(forKey:)`: the switch postdates the feature, so unset must mean
  **on**.
- **Nothing here talks to `LiveActivityManager`.** It watches the same preference
  itself, refuses to create while off, and ends what's on screen when the switch
  drops. So this stays a deletable two lines, and the switch keeps working on its
  own afterwards.

Two ordering rules in `lockScreenSurfaceBinding`:

- Selecting **Live Activity** or **Off** clears `lockScreenNowPlaying` *before*
  writing the Live Activities flag. Each write posts a defaults change, which is
  what wakes this service — write them the other way round and it reads "Lock
  Screen Controls is still on" and turns the flag straight back off.
- Selecting **Now Playing** writes *only* `lockScreenNowPlaying`, and lets
  `reconcileLiveActivities()` do the rest. Setting the Live Activities flag there
  too would give the invariant two owners.

## Ownership: not the view layer

`activate()` is called once from `CueApp.onAppear`. From there the service
watches the model itself: one `for await` loop over a `changes` stream, and
everything that means "re-evaluate" yields into it — an observed model write, the
preference (`didChangeNotification`, so the picker needs no wiring of its own), a
foreground transition, the idle window expiring. Each pass resolves the target
and calls `trackCardState` (track identity, artwork URL, duration, isPlaying,
station, available actions — deliberately *not* `playbackPosition`, which ticks).

`withObservationTracking` is still the mechanism underneath; `Observations`, the
`AsyncSequence` that replaces it outright, is iOS 26 and this ships against 17.
What the stream buys is that its registrations stop needing to be policed. One
can't be cancelled and every pass adds one, so several fire on the next mutation
— `bufferingNewest(1)` collapses that burst into a single pass and the set
converges back to one on its own. That used to take a generation stamp on every
pass to retire the stragglers.

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
| **Background** | The playing group wins, and only a playing group keeps the session | The card is all the user can see, so it follows the music — and nothing is worth holding an audio session for |

Fallbacks, in order: selection (foreground only) → first playing group in
`sorted` order → **the group already on the card** → any mirrorable selection.
The last two are what keep a paused card up when nothing is playing anywhere;
without them, pausing from the Lock Screen would drop the card and leave no way
to resume.

### The idle window

Those last two fallbacks are unconditional in the foreground and **time-boxed in
the background** (`idleGrace`, 3 minutes). Backgrounded with nothing playing, the
session costs an audio-session claim, the `audio` background grant and the
hardware volume bridge — which is how the volume buttons end up controlling a
speaker with no card on screen to explain why. So:

- Something playing → `noteActivity()`, no clock.
- The group **has played** during this session and everything is now quiet → arm
  the window. That's a pause, and the card's play button is how it gets undone;
  tearing the card down would mean opening the app to reverse it. Where the pause
  came from doesn't matter — the card, the app, the Sonos app on another device —
  so `hasPlayed` is sticky for the life of the session rather than tracking the
  last pass.
- The group has **never played** while this card was up → drop it now. There's
  nothing to undo, and this is the case that had the volume buttons pointed at an
  idle speaker.
- Window expires → `stop()`, which clears `hasPlayed` along with everything else.

The expiry needs its own `Task.sleep`: no model state changes at that moment, so
the observation pass would never re-run on its own. Returning to the foreground
retires the clock rather than letting it fire under a user who is looking at the
app.

**"Was playing" cannot be read off `published`.** It looks like the obvious
source and it is wrong, deterministically. `onPlaybackUpdate` writes `isPlaying`
and then calls `notifyLiveUpdate`, which runs this service's `publish()`
*synchronously* — while `@Observable`'s `onChange` defers `evaluate()` to the next
main-actor turn. So the card is already republished as paused before the
evaluation gets to ask, every socket-delivered pause reads as "was already
paused", and the session is released instead of held: pausing from another device
cleared the card. `hasPlayed` is stamped at the end of `evaluate()` instead, from
the model rather than from the card.

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
`AppStorageKeys.speedLaunchNowPlaying` routes `cue://playing` on scene
activation. That fires once per activation rather than on every selection change,
so it can't fight in-app navigation.

## What is actually running while backgrounded

Verified, since the whole design rests on it:

| Running | What it costs |
|---|---|
| The `.nowPlaying` WebSocket (one, on the mirrored group's coordinator) | Idle until the speaker changes something — transport, metadata, or group volume |
| `SonosStreamingService`'s connection check | One ping per socket every 5 minutes, and a rebuild only for a socket that doesn't answer |
| The UPnP ZoneGroupTopology subscription — the FlyingFox listener plus a renewal at 80% of the speaker's ~500 s timeout | Push, not polling: NOTIFY arrives when the topology changes. One renewal request every ~7 minutes |
| `HardwareVolumeService`'s `outputVolume` KVO | Nothing until a volume button or the Lock Screen slider moves |
| `updateTrackInformation` from `liveItemDidChange` | One SOAP fetch per song change — event-driven, not a poll |

**Not running:** `sonosPulse` and `watcher`, the 500–800 ms SOAP loops. They're
what would actually cost battery; everything above is either idle or
edge-triggered.

They're cancelled by `stopMonitoringOffScreen`, on **`.inactive` as well as
`.background`** — and that distinction is the whole point. Locking the phone with
Cue frontmost, holding this feature's audio session, does not reliably reach
`.background`: the scene often parks at `.inactive` and stays there. Keyed on
`.background` alone, as it originally was, both loops kept polling with the
screen off for as long as the phone stayed locked, and the table above was simply
not true on those runs. If you are ever measuring background cost and the number
won't drop, check the scene trace for a `Background` that never came. iPad is
excluded, because there `.inactive` is also what a visible-but-unfocused Split
View window reports.

The topology subscription is the one piece that isn't a WebSocket. It predates
this feature and is push-based, so it doesn't change the cost picture — worth
knowing it's there before concluding "only WebSockets are alive".

**Backgrounded *and* paused is a different regime.** `UIBackgroundModes: audio`
keeps the app alive while it is playing audio; once the silent loop pauses, iOS
is free to suspend us, and everything in the table above stops with it. That is
the accepted cost of the pause mirroring described above, and it's the same
behaviour any paused music app has:

- Pressing play on the card is a remote command, which resumes the app — so the
  normal way out works.
- A resume started from somewhere else (the Sonos app, a speaker button) is not
  seen while suspended, so the card can show paused until the app runs again. It
  self-corrects on the next `publish()`, since `evaluate()` re-resolves and the
  socket reconnects on resume.

Nothing tries to defeat the suspension. Holding the process open by playing
silence through a pause would put us back at a card that can't show a pause,
which is the bug this traded away.

## Why it doesn't poll

The `.nowPlaying` live listener holds one socket, on the mirrored group's
coordinator, for `[.metadata, .playback, .groupVolume]` only. Events write the model in
`SonosService`'s handler and call back through the `.nowPlaying` live-update
observer (keyed by listener, so a second consumer can't silently replace the
first).

Elapsed time is never pushed on a timer. The info center interpolates from the
`elapsedPlaybackTime` + `playbackRate` anchor, so `publish()` re-anchors only
when the card's content changed or the speaker's position drifted more than 2 s
from what the system is already showing (a seek, or a skip from another
controller). Steady-state cost of a playing song: one publish at the track
change, and nothing until the next one.

### The five-minute liveness check, and the hole it used to open

`SonosStreamingService` runs a timer that pings every socket on a five-minute
cycle and rebuilds only the ones that don't answer. That's the liveness
guarantee — a socket that died quietly gets replaced.

It used to rebuild **every** socket, answering or not, and that was the app's
most expensive piece of periodic background work: a teardown, a second of dead
time, a fresh connection and resubscribe per player, a radio wake, and then the
resync below to cover the gap it had just created — forever, with the app off
screen. `SonosWebSocket.isResponsive()` asks the question the rebuild was
implicitly asking. A server that ignores pings reads as dead, so the failure mode
is the old unconditional rebuild rather than a socket left stale.

**The reconnect was never the valuable part, and cutting it alone made the card
unreliable.** Two things the old cycle did as side effects have to survive it,
and both were missing in the first version of this change:

- **Responsive sockets are resubscribed every tick.** A pong proves the
  connection, not the subscriptions. Sonos-side subscriptions lapse, and a group
  id change orphans them, and in both cases the socket keeps answering pings
  while quietly delivering nothing at all. `resubscribeAll()` is a few small
  frames against the socket already open, and Sonos answers it with the current
  state.
- **`onConnectionsRefreshed()` fires every tick, not only after a rebuild.**
  Once the pulse is cancelled off screen this is the app's *only* periodic
  correction. Gating it on a rebuild meant anything a socket failed to deliver
  stayed wrong until the next change — which, on a Lock Screen card mid-song, is
  the rest of the song.

The lesson generalises: this feature's reliability rested on redundancy that was
never written down as redundancy. Before removing any recurring background work,
check what it was accidentally correcting.

The gap is real whenever a rebuild does happen, because sockets only push on
*change*, so anything that moved during it was never reported. Backgrounded there
is no poll to notice.

Worse, `lastLiveItemIDs` still held the id from before the gap, so even the
reconnect's own state event read as "no change" and fired no refetch. A song that
changed while the sockets were down could leave the card on the previous one
until the *next* song change — which is what "the title and art aren't staying in
sync" looks like from the outside.

`SonosEventHandler.onConnectionsRefreshed()` (default no-op, so nothing else has
to care) now fires after the rebuild. `SonosService` forgets the item ids for
every listening player and runs one `updateTrackInformation`, then notifies. One
request per listener per five minutes.

### Publish-path guarantees

Three things stop a correct model from failing to reach the card:

- **`Snapshot` carries the song's identity.** Everything else in it is display
  text, and two tracks can legitimately share all of it — the same song from
  another source, a station replaying an item. Without the identity the dedupe
  reads that as "nothing changed" and leaves the previous card up.
- **A socket (re)subscribe forces a full write** (`published = nil` before
  `publish()`), because that is precisely when the card and the model may have
  drifted while nothing was being pushed.
- **Coming to the foreground re-states the card.** Cheap, and it's the one moment
  the user is looking.

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

`MusicService+Favorite.swift` is byte-identical to the copy on
`claude/live-activity-like-button-57o9qu`, so if both land git merges it without
a conflict. Don't "improve" it here — improve it there.

`LikeButtonView.swift` **no longer is**, deliberately: it kept `@State isFavorite`
in step with the store through an `onChange`, which is observation re-implemented
by hand. The store is `@Observable` and both `MusicSearchService.isFavorite` and
`setFavorite` write it, so the button derives from it instead — no copy, no
`onChange` mirroring, and no way for the two to disagree. Taps write the store
synchronously so the heart still fills on the tap rather than a hop later. What
survives is one `onChange` that does nothing but bounce the symbol, in a single
place regardless of which surface moved the value, gated on `seededTrackID` so
the first read for a song (`nil → true`) doesn't animate what was never a change.
Expect a conflict here when the two branches meet; take this side.

**Where it appears:** surfaces that render feedback commands — CarPlay, some head
units and accessories. The iOS Lock Screen card has no slot for an app-provided
button, so this does not put a heart on the Lock Screen; that surface's path is
the Live Activity's own button. `dislikeCommand` stays disabled — none of these
services take a negative signal.

## Where the phone is

Everything below this line exists because of one beta report, and it's the most
important thing on this page. Paraphrased:

> I came home and music was blasting from my house. My neighbour said it had
> been on all day. Cue showed my Sonos Five pair and an Era 100 playing at
> 100% volume. I have an automation when my phone connects to my car — it
> increases Bluetooth volume to 100% and plays music. Toggling the iPhone volume
> controls setting on and off didn't have any effect.

That is exactly what happened, and both halves of it were this feature:

- **The volume.** iOS remembers an output level *per route* and restores it when
  a route connects. That restore arrives as an ordinary `outputVolume` change —
  there is nothing in it to distinguish it from a finger on the Lock Screen
  slider. In `absoluteMirror` the phone's volume *is* the group's volume, so
  "car stereo at 100%" became "Sonos Fives at 100%", in one step, from an empty
  house.
- **The play.** Holding the session means holding `MPRemoteCommandCenter`, so
  Cue was the app the automation's play command went to. A Shortcut aimed at a
  car stereo started the speakers in the living room.

Three rules follow, and they're deliberately redundant — each one alone would
have prevented this:

**1. The volume bridge reads a switch, and it's the same switch the player screen
reads.** `AppStorageKeys.useHardwareVolumeButtons` — *Use iPhone Volume
Buttons*. This path used to take the bridge unconditionally,
which is why toggling the switch "didn't have any effect": only
`HardwareVolumeControlModifier` ever read it. The Lock Screen slider and the
hardware buttons are the same system volume, so there is no honouring the switch
for one and not the other — and certainly not honouring it on one screen while
ignoring it from the Lock Screen with the app closed. Off, the slider moves the
phone's own (inaudible) volume and the speakers are left alone.

**It is on when unset**, read through `UserDefaults.hardwareVolumeButtonsEnabled`
— never `bool(forKey:)`, which reads unset as off and would leave the default
unreachable for everyone who never opened Preferences, i.e. exactly the people a
default is for. All three call sites have to agree on that literal: the two
`@AppStorage` declarations default to `true` as well, or the buttons would
control the group on one surface and the device on the other. Controlling the
speaker is what people expect of a speaker controller, and the surface this
drives is itself the default with Super.

That default is only defensible because of rules 2 and 3 below. **Do not weaken
either of them while this stays on** — on its own, rule 1 was never what made the
reported failure impossible; it was the switch the user had already tried.
Someone who turned it off keeps it off through the change: an explicit `false`
reads as false, which is the whole reason for the accessor rather than a
registered default.

The row moved out of **Playback** and into the **Lock Screen** section for the
same reason, directly under the picker and shown only while Now Playing is the
selected surface — see "Live Activities" for why those rows appear and disappear
rather than greying. Once the switch decides whether the Lock Screen's slider
reaches the speaker, a section away from the surface it gates is two volume
controls with an invisible dependency between them.

**The switch means exactly one thing, and the player screen was made to agree.**
`HardwareVolumeControlModifier` used to read the switch alone, so the same key
turned on two features with different gating: a Super-and-Now-Playing one on the
Lock Screen, and a free, always-available one in the app. That was survivable
while the switch defaulted to off and lived in **Playback**. It stopped being
survivable the moment the switch defaulted to *on* and moved into a Super-gated
section shown only under Now Playing — a non-subscriber, or anyone on Live
Activity, would get their volume buttons pointed at a Sonos group with the only
switch for it greyed out or not on screen at all. Which is the complaint that
started this branch, with the toggle taken away as well.

So the modifier now requires the same three conditions the row does — the switch,
`lockScreenNowPlaying`, and an active subscription. The row is present and
editable in exactly the cases where it changes something, and there is no state
this leaves someone stuck in. It reads the *preference* rather than
`NowPlayingSessionService.isActive`, so the buttons still work on the player
screen when nothing is playing yet.

The cost is real and was chosen: in-app hardware volume buttons are now Cue
Super, and only while Now Playing is the selected surface. If they should be free
again, that's a second key with its own row — not a second meaning for this one.

**2. Off the built-in speaker, the whole feature stands down.**
`AudioOutputRoute.isExternal` is true for anything that isn't
`.builtInSpeaker`/`.builtInReceiver` — Bluetooth, CarPlay, AirPlay, wired or
wireless headphones. On such a route two things are true that aren't true on the
phone's own speaker: the phone's volume is *audible and someone else's*, and the
device on the other end can issue transport commands (a head unit's play button,
an inline remote, an AirPods stem, an automation that fires on connect). None of
that is Cue's to receive when the user has plainly gone somewhere else with the
phone, so `canMirror` is false and `evaluate()` calls `stop()`.

Details that matter:

- `canMirror` is **split from `isEnabled`** rather than folded into it, because
  `reconcileLiveActivities()` reads `isEnabled`: a drive to the shops must not
  look like turning the feature off and put Live Activities back.
- The route observer calls `stop()` **synchronously** rather than only yielding
  into `changes`. What follows a car connecting is a play command, immediately,
  and the drain is a main-actor turn away.
- `perform()` re-reads the route itself before running any command. Connecting
  changes the route and *then* posts about it, while the automation races the
  same moment — `currentRoute` is the only account of where the phone is that is
  guaranteed current at the instant a command arrives.
- **The route is cached in `isRouteExternal`, not read live, and it unlatches
  asymmetrically.** Any route change may set it; only `.oldDeviceUnavailable`
  (the other device actually going away) or a foreground transition may clear
  it. Read live, this oscillates: standing down deactivates the session, the
  route reported for an *inactive* session isn't dependable, and if it reads as
  built-in we come straight back — activating routes us to the car again, and we
  stand down once more, flickering the user's car audio for the length of the
  drive. Neither unlatching signal can be produced by our own teardown, so the
  loop can't close.
- The foreground clause is the recovery for the case where the unlatching route
  change is never delivered: standing down gives up the `audio` background mode,
  so the app is free to be suspended, and a device that disconnects while it is
  suspended posts to nobody.

**3. The bridge itself refuses what no gesture could have done.** Both of these
live in `HardwareVolumeService`, so they hold even if a caller gets the gating
wrong:

- **Suspended on an external route.** The claim is kept and the bridge goes
  inert in both directions: `syncSystemVolume()` won't push the group's level
  onto a car stereo, and the KVO handler won't read that stereo's level back.
- **A settle window after every route change** (`routeSettleDelay`, 1.5 s). The
  restored level doesn't arrive with the notification, it lands a beat later, so
  the notification alone doesn't cover it. `savedVolume` is dropped at the same
  moment — restoring a level captured on one route onto another is the same bug
  facing the other way.
- **A jump guard in absolute mode** (`maxGestureStep`, four `systemVolumeStep`s).
  A hardware press moves the system volume exactly one step and a slider drag
  arrives as a stream of small changes, so nothing a hand can do lands four steps
  away in one callback; anything that does was set programmatically. It's
  refused, and the phone is put back where the group actually is — the echo
  filter catches that write, so it can't recur. Four rather than two leaves room
  for a coarse or dropped drag. The cost is that a *tap* on the Lock Screen
  slider far from its current position may snap back instead of taking; drag it
  and it works. That trade is deliberate.

None of the three is a substitute for the others. Rule 1 is the user's stated
preference, rule 2 is about where the phone is, rule 3 is about what a human
hand can physically do — and the reported failure would have had to beat all
three.

## Volume

While the session is held the phone's own volume is inaudible, so the hardware
buttons and the Lock Screen slider are re-pointed at the group — **if the user
turned that on**, and only on the phone's own speaker. See "Where the phone is"
above; the rest of this section describes what happens once both gates pass.
`HardwareVolumeService` runs as `owner: .session` with `configuresAudioSession:
false`: it skips the
`.ambient` reconfiguration that would forfeit the Now Playing claim, and keeps
its `outputVolume` KVO alive while backgrounded — which is exactly when the Lock
Screen slider is used. The service arbitrates ownership itself (`Owner.session` outranks
`Owner.playerScreen`), so the player screen's modifier claims and releases
without knowing what else exists; its `owner` is observed, which is what makes
the modifier take the bridge back when the session ends. The `MPVolumeView` is parked in the key window; its slider only
exists inside a window.

### iPad

Nothing here is gated by idiom — same session, same card, same bridge. Two
things differ in practice:

- **The system player's volume slider is the system's call.** A beta report from
  an iPad had artwork and transport but no slider, with the hardware buttons
  still controlling the speaker. Nothing in this feature draws or withholds that
  slider; we only make the phone's volume *be* the group's. The test that settles
  it is Apple Music on the same iPad: if its Lock Screen card has no slider
  either, it's iPadOS. Control Center's slider is the same system volume, so it
  moves the group either way.
- **A scene can be disconnected under the session.** The session outlives any
  window, and on iPad a second window closing or Stage Manager rearranging really
  does take the `MPVolumeView`'s host away. The failure is quiet and asymmetric —
  the hardware buttons keep working, since the `outputVolume` KVO and
  `setGroupVolume` don't need the slider, while `syncSystemVolume()` writes into a
  view that is in no hierarchy — so `run()` re-attaches whenever
  `volumeView?.window` is nil, not only when the mirrored group changes.

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

**The inbound half needed a socket event, not just observation.**
`syncSystemVolume` runs off `trackCardState`'s read of `group.groupVolume`, so it
follows whatever writes the model — but backgrounded, nothing did.
`SonosService.onVolumeUpdate` was the protocol's empty default, and in the
foreground the 500 ms SOAP pulse re-read `groupVolume` and hid that. With the
pulse cancelled, a change made on the speaker or in the Sonos app never arrived
and the slider drifted. So the `.nowPlaying` listener subscribes `.groupVolume`
alongside the transport, and the handler writes `group.groupVolume` (behind the
same `isEditingVolume` guard the poll uses, or a drag gets shoved back under the
user's finger by its own echo). `playerVolume` is deliberately not handled:
different namespace, nothing subscribes to it, and it's the wrong number for a
surface that controls the group.

Echo filtering differs by mode for the same reason: relative can compare against
`restorePoint` because its writes always land there, absolute has to remember
its own recent writes (`recentSystemVolumeWrites` — a short list rather than one
value, because writes burst around a regroup and the echo of one write compared
against the memory of a later one read as a gesture). Hardware presses are
recognised inside absolute mode by their signature — a whole-system-step delta
in a single change, which a drag's stream of pixel-sized changes can't match —
and sent as the same 1-point relative step the player screen's mode sends, with
the slider then re-seeded from the group's level so the next press measures from
the truth. Drags keep the absolute scale. (Presses used to be mapped through the
absolute scale too, which made each one a ~6-point jump on the group — the
system has 16 steps — and was reported as the volume becoming hard to adjust.)

**Absolute mode's tolerances are half a system step, and that is not an
epsilon.** The system volume has 16 positions, so `syncSystemVolume` writes an
arbitrary scaled level and gets back the nearest step — up to 0.031 away from
what it wrote. Both tolerances were 0.005, a sixth of that, and the consequences
compounded: the write went out even when the target snapped to the step the
slider was already on, and the echo it produced was then read as *the user*
moving the volume. That sent a real `setGroupVolume`, which pulled the group's
level onto the phone's 16-point grid a point or two off where the user set it,
and the speaker's echo of that came back through the socket as another model
write — a whole round of work per group-volume change, backgrounded, for a
slider that couldn't render the difference. Half a step is the exact boundary,
not a fudge factor: a genuine press is a whole step from the current position, so
it is never closer than half a step to what we wrote and nothing real is
swallowed.

## Shape

Everything app-side lives in **`Cue/Services/NowPlaying/`** — the whole feature
is that folder plus four lines elsewhere. The project uses Xcode 16 synchronized
folders, so the directory *is* the group; no `project.pbxproj` entry to keep in
step.

### A retired bring-up must not go quiet

`beginSessionIfNeeded()` is asynchronous and `stop()` can land while it's in
flight; the generation stamp retires it and releases the session it took. But
`run()` can't have started a replacement in that window — `beginSessionIfNeeded`
was blocked by `isStartingSession`, which the retired task only clears a line
earlier — so the feature was left with no session and nothing scheduled to try
again. Backgrounded, "the next model change" can be never. The retired path now
yields to `changes` so a fresh pass decides again.

This became reachable when the idle window started calling `stop()` as a matter
of routine rather than only when the feature was switched off.

## Shape (cont.)

`AudioSessionArbiter` sits in the folder too, which needs a word: it is deliberately
feature-agnostic — `AudioPlaybackService` asks *it*, never this feature — and the
folder is about lifetime, not dependency direction. It's here because it exists
only for this feature and goes when the feature goes.

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
- **The bring-up traces are gone.** While this was being debugged on device
  every step printed behind a `🎛 NowPlaying —` prefix; that came out for
  release. What remains is two `Logger.error` calls in `SilentAudioSession` for
  the paths that lose the card outright (the session refusing to activate, the
  silent loop failing to start) and the existing `SonosAPI` logger for a
  transport command the speaker rejected. `perform(_:)` lost its `name`
  parameter with the trace it existed for.
- **The silent session is the one continuous cost, and it is tuned for it.** It
  renders for as long as the speaker plays, with the app off screen, and that
  cost is a per-callback overhead times `sampleRate / bufferFrames`. So the
  session asks for a 100 ms I/O buffer (`setPreferredIOBufferDuration`, before
  activation or it isn't considered) — ~10 wake-ups a second instead of the
  `.playback` default's ~43 — and the WAV is generated at
  `AVAudioSession.sampleRate` rather than a fixed 44.1 kHz, so there is no
  sample-rate converter in the path resampling silence into silence on the
  48 kHz every current iPhone runs. iOS clamps the buffer request to what the
  route allows; a refusal just leaves the default standing. `reclaim()` rebuilds
  the player when a route change moved the hardware rate, or the converter comes
  back.
- **Nothing in the app may run a view clock while this feature is on.** The
  session keeps the process alive on the `audio` background mode, so a
  `TimelineView` or a `.task` loop that would normally stop when its view leaves
  the screen doesn't — it runs against the Lock Screen with nothing drawn. Two
  measurements below record what that costs. `MarqueeText` was doing exactly
  this in shipped code: an unpaused `TimelineView(.animation)` on the player
  screen *and* in `MiniPlayerView`, which is mounted nearly everywhere, so it was
  effectively always live. It first paused on `scenePhase != .active`; it has
  since dropped the timeline altogether for a `.task` loop that animates an
  `.offset` (keyed on the scene phase, so it is cancelled off screen), which
  renders nothing while resting and doesn't re-evaluate `body` per frame while
  scrolling.
- Also: the silent WAV is cached per rate rather than rebuilt per activation; the
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

### Tried and reverted: interpolating the player screen's scrubber

The card and the player screen disagree by a second or two, for the whole of a
song. Worth understanding before anyone tries again, because the cause is not
obvious and neither is the reason the fix isn't worth it.

**Why they disagree.** `Room.playbackPosition` is not a clock. It is parsed from
AVTransport's `RelTime`, which Sonos formats as `h:mm:ss` — so every reading is
**truncated to a whole second** — and it only moves when the SOAP pulse writes
it, every 500–800 ms and already a round trip stale. `PlaybackView` binds it
straight to the scrubber, so the player screen is a 1 Hz stepper showing a number
up to a second behind. The card publishes an anchor and a rate and lets iOS
interpolate, anchored to whatever reading was current at the track change. Two
different kinds of clock over one source, and nothing corrects the gap because
every deadband in the chain is wider than it: the socket only writes position
when it is off by >1000 ms, and `driftTolerance` is 2000 ms.

**Why the obvious fix is wrong.** Re-anchoring the card off the model more often
makes the card quantized and laggy to match the worse surface, and it can't be
tuned: `driftTolerance` cannot go below one second, because the truncation alone
puts a *correct* interpolation up to a full second above the reading. Tighten it
and the scrubber snaps backwards on every poll.

**Why the right-looking fix is also not worth it.** Two attempts at giving the
player screen the same interpolation both cost far more CPU than they were worth,
measured on device:

- A `.task` loop reading the clock 4× a second: **5% → 15% backgrounded.**
  `.task` is tied to a view's *lifetime*, not its visibility, and this feature
  deliberately keeps the app alive in the background holding the audio session —
  so the loop ran with the phone locked, for a scrubber nobody could see.
- `TimelineView(.animation(minimumInterval: 0.25, paused:))` reading a pure
  `position(at:)`, which should have suspended when nothing was drawn:
  **~30%**, and the bar still didn't render smoothly.

The second result is the one to explain before trying a third time — it says the
cost is not the read rate, and probably not the schedule either. Prime suspect:
`VibeSlider` animates its progress capsule with `.animation(.interactiveSpring,
value:)`, so every new target restarts a spring that never settles, and layout
runs every frame regardless of how rarely the value moves. Anything that feeds
that slider a continuously-moving value inherits it. A fourth attempt should
start with Instruments on `VibeSlider`, not with a different clock.

**Do not** fix it by writing extrapolated positions back into
`Room.playbackPosition`. It is documented as what the device reported or a local
seek; a view fabricating values into it reaches every other surface and the
card's own `resolve` input.

## Removing this feature

After the dependency inversions, no pre-existing type names it. To remove:

1. Delete `Cue/Services/NowPlaying/` and `Docs/LockScreenNowPlaying.md`.
2. Delete the `activate()` call in `CueApp.onAppear`, the `lockScreenNowPlaying`
   key, and `UIBackgroundModes` from `Info.plist`.
3. In `PreferenceScreen`, drop the `nowPlaying` case from `LockScreenSurface`
   along with `lockScreenNowPlaying` — the picker becomes `Live Activity | Off`
   and keeps working. Delete `reconcileLiveActivities()`, its `evaluate()` call,
   and the `liveActivitiesSuspendedByLockScreen` key. The Live Activities switch
   itself stays: `LiveActivityManager` reads it directly and it's a useful
   control on its own.
4. In `AudioPlaybackService`, drop the `AudioSessionArbiter.shared.handBack()`
   line (or leave it — with nothing claiming, it returns false and the original
   behaviour stands).
5. Optionally simplify `HardwareVolumeService` back to one owner and one mode.

What stays, because it's independent of the Lock Screen and fixes real
foreground behaviour: the whole `SonosService+LiveListening` registry, the
socket event handlers in `SonosService+SonosEventHandler`, `SuperBadge`,
`PlaybackPositionAnchor` (a general utility any media surface can use — the
Live Activity has the same interpolation problem), and
`Cue/Services/AudioOutputRoute.swift` — `HardwareVolumeService` uses it to keep
the player screen's bridge off a car stereo too, which has nothing to do with
the card.

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
