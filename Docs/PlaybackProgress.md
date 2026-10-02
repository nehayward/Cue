# Playback Progress

How Cue tracks and draws playback position — a speaker's and this device's —
in the player's bar, the mini player's line, the play-button rings, the TV
player and the Lock Screen card, and why it works this way. Ported from Clic
(its PR #103, 2026.9); the on-device half is Cue's own.

## The problems this fixed

| Symptom | Cause |
|---|---|
| Lock Screen bar carried on from the previous song after a track change | A new track was written to the model without its position. Backgrounded there's no poll, so the Now Playing card started each new song at the old song's position. |
| Player opened on a stale position, then slid into place | The bar drew the stored position, which only moves when something writes it, and animated every change. |
| Scrubber jumped back a moment after release | Seeks are sent in whole seconds and the speaker buffers before resuming; the bar kept counting, and the next report pulled it back. |
| Skipping briefly showed the old song's time | For a moment after the command the speaker still reports the outgoing song. |
| Play button flickered on lock / unlock | A failed `GetTransportInfo` came back as `.transitioning` (pulse) and was read as "paused" by the Live Activity refresh (play icon). |
| CPU while idle and locked | A hidden, endlessly repeating symbol animation on every speaker's artwork, timelines that kept ticking off screen, and model writes of unchanged values on every poll. |

## The model: `Room` (SonosKit)

`Room.playbackPosition` is the last position the speaker reported (or a local
seek set). It is **not** where playback is now — it only moves when something
writes it: the pulse (foreground, selected group only) or a socket event.
Everything below builds on that.

### The position belongs to the track

`Room.track` has a `didSet`: when `track.unique` changes, `playbackPosition` is
set from the incoming `Track.playbackPosition` (parsed alongside it from
`GetPositionInfo`). One rule in the model instead of writes at each of the ~29
`track =` sites. In-place edits to the same song (late artist / duration
reconciles) don't touch it.

### A running estimate

```swift
room.estimatedPlaybackPosition(at: .now)
```

Runs `playbackPosition` forward from `playbackPositionStampedAt` while
`isClockRunning` (`isPlaying && !isTransitioning`), clamped to the track's
length. Every progress display draws this, never the stored number.

- **Stopping the clock** (pause, buffering) folds the elapsed time into
  `playbackPosition`, so the bar stays where it was showing.
- **Starting it** only restamps, so time spent stopped doesn't count.
- The socket records `BUFFERING` / `TRANSITIONING` as `isTransitioning`
  (without touching `isPlaying` — buffering isn't a pause).

### Filtering reports

`updatePlaybackPosition(_:at:)` is the single place reports land:

- **While the clock runs**, a report within `reportTolerance` (2 s) of the
  estimate is dropped. SOAP `RelTime` is whole seconds and arrives a round trip
  late, so polls sit up to ~1.3 s behind on their own; taking them would pull
  the bar back every tick. Anything further off is a real jump and is taken.
- **While stopped**, a report is written only if it changed.
- Socket and poll call sites pass every report through; they don't pre-filter.

### Seeks and skips

```swift
room.beginSeek(to: milliseconds)  // called by SonosService.seek(to:on:)
room.beginSkip()                  // called by SonosService.next / previous
```

The bar goes to where the command lands — the **whole second** actually sent
(`REL_TIME` has no fraction), or 0 for a skip — and holds there:

- Reports far from the target were read before the command landed: ignored.
- The target itself, repeated while the speaker buffers: held.
- A position **past** the target while the clock runs: confirmed; the clock
  restarts from it.
- A new track ends the hold (its `didSet`).
- After `seekTimeout` (3 s) with no confirmation, the bar runs regardless.

Because this lives in `SonosService.seek` / `next` / `previous`, every entry
point is covered: player, mini player, menu commands, Lock Screen remote
commands, TV, Dock menu, intents.

### Transport status

`PlaybackStatus.unknown` means the speaker couldn't be read (request failed,
reply didn't parse). It is not a state, and nothing acts on it.
`PlaybackStatus.isTransitioning` is `nil` for it; polled states go through
`Room.apply(polled:)`, which writes only what the status says and only on
change.

### Write only on change

An `@Observable` setter notifies every observer even when the value is the
same. The pulse runs every 500–800 ms, so `isTransitioning`, `volume`,
`isMuted` and repeated seek reports are all compared before writing.

## This device: `LocalPlaybackService`

The same idea for Cue's own player. `progress` is a computed property: the
player's clock as last read (`progressAnchor`), run forward while
`isPlaying`, clamped to `duration`. Stopping folds the elapsed time into the
anchor; starting only restamps it. Writing `progress` (a seek, a new song, a
restore) sets the clock.

The 0.5 s poll reports through `noteProgress(_:)`: while playing, a reading
within `progressTolerance` (0.5 s) of the estimate is dropped, since AVPlayer
and MusicKit report their time exactly and the clock already has it; paused,
it's written only when it changed. Everything that reads `progress` — the
scrubber, the mini player, the hand-off snapshot, the Now Playing card, play
reports — gets the estimate.

## The views

### `PlaybackTimeline` (VibesDS)

```swift
PlaybackTimeline(
    isRunning: room.isClockRunning && !isScrubbing,
    minimumInterval: ProgressRedraw.interval(forDuration: duration, length: barWidth, scale: displayScale),
    position: { isScrubbing ? room.playbackPosition : room.estimatedPlaybackPosition() }
) { position in
    // slider, time labels…
}
```

Redraws its content with the running position, and only while that's worth
doing. It is paused unless **all** of these hold:

- the scene is visible — Cue's audio session keeps the process alive behind
  the Lock Screen, and a lock with Cue frontmost doesn't reliably reach
  `.background`. `.inactive` counts as visible on iPad and the Mac, where it's
  an unfocused window, not a locked screen;
- the view is on screen (`onAppear` / `onDisappear`);
- `isRunning` — the clock is running and nothing (a finger) holds the value.

Built on `TimelineView(.animation(minimumInterval:paused:))`, which is already
display-link driven, throttled and paused by SwiftUI — no `CADisplayLink`, UIKit
bridge or lifecycle to manage.

| Where | Redraw rate |
|---|---|
| Player bar (`GroupPlaybackScrubber`, `LocalPlaybackScrubber`) | Once per pixel of progress (`ProgressRedraw.interval`: song length ÷ bar pixels, 1/30 s – 1 s). ~0.17 s for a 3-minute song on a phone. |
| TV player bar (display-only) | 0.25 s |
| Play-button rings (`MiniPlayerView`, `MediaControlsView`) | 1 s |
| Mini player line (`MiniPlayerProgressLine` in `CueApp.swift`) | Once per pixel, as the player bar |

The player bar uses `valueAnimation: nil`: it moves frame by frame on its own,
and a seek or track change should land instantly, not sweep.

### Scrubbing

`GroupPlaybackScrubber.scrubbingChanged(_:)`: on the first touch it starts from the
on-screen estimate and sets `isEditingPlayback` (keeps polls and socket events
off the position); on release it clears that and calls `SonosService.seek`, in
the same turn, so `beginSeek` decides which reports count from there.

### Play/pause pulse

`sustainedPulse(isActive:after:)` (VibesDS) pulses only once `isTransitioning`
has held for 600 ms, and only while the scene is active — a real wait still
shows, a blip (socket re-subscribing on lock / unlock) doesn't. Used by
`PlaybackIconView`, `LargePlayerView` and `TVPlayerView`.

### Artwork alarm badge

`ArtworkBadgeView` builds the alarm symbol only while an alarm is running, and
animates its wiggle only while active. It used to be always present, hidden with
opacity, animating every frame on every speaker's artwork.

## Measured results

From Instruments SwiftUI traces on device (iPhone, five speakers):

| Phase | Before | After |
|---|---|---|
| Phone locked | ~300 SwiftUI updates/s, nonstop | 0 (brief bursts only for real events) |
| Idle on the speaker list | ~300/s | ~0 |
| CPU while locked | elevated | ~1–2 % |

## Files

| Area | Files |
|---|---|
| Model | `Packages/SonosKit/Sources/SonosKit/Models/Room.swift`, `Models/PlaybackStatus.swift` |
| Service | `SonosService.swift` (`seek`, `next`, `previous`, sweeps, `adoptGroups`), `SonosService+SonosEventHandler.swift`, `SonosAPI.swift`, `Parsers/XMLParserSonos.swift` |
| Views | `Packages/VibesDS/Sources/VibesDS/PlaybackTimeline.swift`, `Icons/SustainedPulse.swift`, `Icons/PlaybackIconView.swift`, `Cue/LargePlayerView.swift` (`GroupPlaybackScrubber`), `Cue/Views/PlayerView.swift` (`LocalPlaybackScrubber`), `Cue/CueApp.swift` (`MiniPlayerProgressLine`), `Cue/MediaControlsView.swift`, `Cue/Search/MiniPlayerView.swift`, `Cue/ArtworkBadgeView.swift`, `TV/TVPlayerView.swift` |
| Callers | `Cue/Services/NowPlaying/NowPlayingSessionService.swift`, `Cue/LiveActivityManager.swift`, `Cue/CueApp.swift`, `Cue/Services/PlaybackRoute.swift`, `Widgets/ControlWidgets/PlaybackControlWidget.swift` |
| This device | `Cue/Services/LocalPlaybackService.swift` (`progress`, `estimatedProgress(at:)`, `noteProgress(_:)`) |
| Tests | `Packages/SonosKit/Tests/SonosKitTests/RoomPlaybackPositionTests.swift` |
| Tooling | `Scripts/export-swiftui-trace.sh` |

## Rules for future changes

- Draw progress from `estimatedPlaybackPosition()`, through `PlaybackTimeline`
  — never from `playbackPosition` directly, which only moves on jumps.
- Report positions through `updatePlaybackPosition(_:)`; don't pre-filter at
  the call site.
- Anything that moves the position on the speaker goes through
  `SonosService.seek` / `next` / `previous`, so the bar holds correctly.
- Don't assign an `@Observable` property on a timer or poll without comparing
  first.
- Anything that animates on its own (timelines, repeating symbol effects) must
  stop when the scene isn't active and when it isn't visible — the process
  keeps running behind the Lock Screen.

## Profiling

Record with the **SwiftUI** template in Instruments on device, then:

```sh
Scripts/export-swiftui-trace.sh path/to/recording.trace   # latest run; --run N for another
```

It writes a small `summary.txt` (and zip): update counts and causes per second,
app lifecycle, hitches, and the main thread's stacks during each hang.

## Known, out of scope

- A ~300–500 ms main-thread stall when the app goes to the background is mostly
  iOS's app-switcher snapshot laying out the player
  (`_performSnapshotsWithAction`), inflated by Instruments' own tracing.
- The player's glass / blur effects cause occasional dropped frames (41–66
  offscreen passes in traces).
- `NowPlayingSessionService` still uses `PlaybackPositionAnchor` for the Lock
  Screen card; it could use `Room.estimatedPlaybackPosition()` directly.
