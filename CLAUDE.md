# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cue is a multi-platform SwiftUI music player that also controls Sonos speakers. It plays Apple Music, Plex, Subsonic, TuneIn and local files on the device itself (`LocalPlaybackService`) and hands the same queue to a Sonos group (`PlaybackRoute`). It provides native apps for iOS, iPadOS, macOS and tvOS, and includes a menu bar app (Cue Mini). Widgets and Live Activities are switched off for now (see Platform-Specific Features).

## Product Priorities

1. **Best music player first.** Cue is a player that happens to be an excellent Sonos client, not a Sonos remote with a player bolted on. Playback, queue, library, search and Now Playing must be complete on the device alone, with no speaker on the network.
2. **Best Sonos client second.** Everything the device can play must also play on a Sonos group, and the hand-off between the two must be seamless (`PlaybackRoute`).
3. **Every service must play on the device and on Sonos.** A service belongs in Cue only if its audio can be played by the device (MusicKit, a direct stream URL, or a local file) *and* by a speaker. Services whose audio only a speaker can reach are not supported, however popular they are on Sonos. Today that rule excludes Spotify, Tidal, Deezer, SoundCloud, Pandora, Sonos Radio and the speaker's own Music Library. See `Ideas/device-first-services.md` for the audit and the removal plan.

When a change forces a trade-off between the player and the Sonos client, the player wins. Do not add a service, feature or screen that only works when a speaker is present.

## Session Workflow

These rules apply to every session on the Mac (started with `Scripts/claude-remote.sh` and driven from the phone).

### Branch per session
- At the start of every session, before editing anything, create a new branch from the latest `main`: `git fetch origin main && git switch -c claude/<short-topic> origin/main`. Name it after the task, for example `claude/queue-swipe-actions`. If the working tree has uncommitted changes, ask before switching.
- Make every change and commit of the session on that branch. Do not commit to `main`, and do not start another branch in the same session.
- Push the branch with `git push -u origin <branch>` when work is committed. Merge to `main` only when asked.

### Deploy to the iPhone after every build
- When you build the iOS app, run `Scripts/deploy-to-iphone.sh` instead of a simulator build. It builds the `Cue` scheme (Debug) for the connected iPhone, installs it and launches it. The user tests on the phone, so a change is not finished until it has been deployed.
- On failure, it prints the compile errors and writes the full log to `build/device-build.log`. Fix the errors and run it again.
- If it reports that no iPhone is connected, build for the simulator instead (`xcodebuild -project Cue.xcodeproj -scheme Cue -destination 'generic/platform=iOS Simulator' build`) and tell the user the phone was not reachable.
- The script also installs the watch app from the build straight onto the paired Apple Watch (`Scripts/list-watches.py` finds it; `CUE_WATCH=<name or UDID>` picks one, `--no-watch` skips it), so the watch's reason shows in the output when it refuses. The watch has to be known to Xcode (Devices and Simulators) with Developer Mode on.
- Other targets (Mac, TV, Cue Mini) build with `xcodebuild` as usual; only the iOS and watch apps are deployed.

### Logs and crashes from the iPhone
- To check runtime behaviour, deploy with `Scripts/deploy-to-iphone.sh --logs [seconds]` (default 30), or relaunch without rebuilding with `Scripts/iphone-logs.sh [seconds]`. Ask the user to reproduce on the phone while it captures. It shows the last 200 lines; the full capture is in `build/device-console.log`. Set `CUE_LOG_FILTER=<text>` to see only matching lines. `print` and `Logger` output both appear.
- When the user says the app crashed, run `Scripts/iphone-crashes.sh` (`--count N` for more) before reading code. It pulls Cue's newest crash report into `build/crashes` and prints the exception, the crash message and the crashed thread with Cue's frames symbolicated. If it says the phone's build doesn't match the local one, deploy again and ask the user to reproduce the crash.
- For crashes in an extension, pass `--process Widgets` (or the extension's executable name).

## Build & Development Commands

This is an Xcode project with multiple targets and schemes:

### Build Commands
- **Open in Xcode**: `open Cue.xcodeproj`
- **Build main app**: Use Xcode's build system (⌘+B) or select specific schemes
- **Available schemes**: Cue, Cue (Mac), Cue (TV), Cue (Watch), Cue Mini, Cue [Free], Vision [Free], QueueAction, Widgets

### Testing
- **Run tests**: Use Xcode's test navigator or ⌘+U
- **Package tests**: Each Swift package in `/Packages` has its own test suite
- **Integration tests**: Located in package test directories (e.g., `Packages/SonosKit/Tests`)

### Configuration
- **Debug**: Uses `Configuration/Debug.xcconfig`
- **Beta**: Uses `Configuration/Beta.xcconfig`  
- **Release**: Uses `Configuration/Release.xcconfig`

## Architecture

### Core Package Structure
The app is built around several Swift packages in `/Packages`:

1. **SonosKit** - Core Sonos integration and device communication
   - `SonosService` - Main service class managing Sonos system state
   - `SonosAPI` - Network communication with Sonos devices
   - XML parsers for Sonos responses
   - Device discovery and monitoring

2. **MusicSearchKit** - Music service integrations (also linked into the watch app, which browses Plex and Subsonic with it). A dynamic framework: the iOS app gets it embedded through SonosKit, but the watch links it directly, so its target embeds it in its own Embed Frameworks phase
   - Apple Music, Spotify, Plex, Tidal, TuneIn, SoundCloud APIs
   - Authentication services for each platform
   - Search result parsing and models

3. **SubscriptionKit** - In-app purchase management
   - RevenueCat integration for subscriptions

4. **Defaults** - Centralized app settings and storage keys
   - `AppStorageKeys`, `CloudKeys`, `GroupStorageKeys`
   - Feature flags and preferences

5. **Analytics** - Event tracking and analytics
   - User behavior and app usage metrics

6. **VibesDS** - Custom UI design system
   - Reusable SwiftUI components and styles

7. **WatchSync** - What the iPhone and the watch app share (pure Foundation, tested with `swift test`)
   - `WatchPicks`/`WatchPick` (what's chosen to be on the watch, by id, merged per pick), `WatchCredentials` (the iPhone's sign-ins), `WatchKeys`, `WatchDownloadQuality`, `WatchSyncMessage` (the application context each side sends)
   - `TransferRateMeter` and `RouteEstimator`, which tell the watch's own Wi‑Fi from the iPhone relay by speed
   - `WatchWidgetState`, what the watch app leaves in the app group (`group.dance.cue`) for its widgets

### Main App Structure
- **CueApp.swift** - Main app entry point with shared services
- **Router.swift** - Navigation and routing system
- **Services/** - Core app services (ImageCache, Queue, PlayHistory)
- **Search/** - Search functionality across music services
- **Library/** - Music library browsing and management
- **Routing/** - App navigation and destination management

### Platform-Specific Apps
- **CueMini/** - macOS menu bar app for quick controls
- **TV/** - tvOS app optimized for Apple TV
- **CarPlay/** - the iPhone app's CarPlay scene (built by the Cue target only; there is no separate CarPlay target)
- **Watch/** - watchOS app (`Cue (Watch)`, embedded in the iOS app): plays Plex and Subsonic songs downloaded to the watch. See Apple Watch below
- **WatchWidgets/** - the watch's widget extension (`Widgets (Watch)`, embedded in the watch app): the Smart Stack / watch face widget and the Shuffle Downloads control
- **Widgets/** - iOS/macOS widgets, controls and Live Activities (target kept, not embedded in the apps for now)
- **PlayAction/** - Share sheet extension for queuing music
- **Website/** - cue.dance, a Cloudflare Worker (see `Website/README.md`). Release pages and the in-app What's New JSON come from `Website/src/content/releases.js` (starting at 2026.1), and `/help` and `/releases/<version>` are opened by the app's web views

### Key Services
- `SonosService.shared` - Central Sonos system management
- `MusicSearchService.shared` - Music service search coordination
- `SubscriptionService.shared` - Subscription and paywall management
- `PlayHistoryService.shared` - Track play history
- `AlertService.shared` - App-wide alert handling

## Development Guidelines

### Code Organization
- Use `@Observable` for SwiftUI state management
- Services follow singleton pattern with `.shared` instances
- UI components are organized by feature area
- Packages are used for modular, reusable functionality

### Key Patterns
- **Router-based navigation** using `RouterDestination` enums
- **Service injection** through SwiftUI environment
- **CloudStorage** for synced user preferences
- **AppStorage** for local device settings
- **One player for both routes**: the player, the mini player and the queue panel draw `PlaybackRoute.presented`, a `PlaybackController` (`Cue/Services/PlaybackController.swift`: `LocalPlaybackService` for this device, `SonosGroupController` for a group, times in seconds on both), not a branch on `route.group`. A route switch changes what the one set of views reads; while a hand-off carries the queue across, `presented` holds on the source (`PlaybackRoute.hold`) until the target is playing the same song with its cover cached, so the player never drops to the speaker's old track mid-switch (transport rests meanwhile, and the bar follows what's actually heard through `setHoldClock`; the hold ends 12 s after the source stops, 30 s at most). Speaker-only extras (TV mode, its artwork badges and menu, room volume) read `controller.group`. Transport, queue and drops go to `PlaybackRoute.controller` / `route.group` (the route itself). Don't branch a player surface's whole body on the group: a view in two `if` branches is rebuilt on every switch
- **Playback progress** is a running clock, not a ticking number: `Room.estimatedPlaybackPosition()` for a speaker, `LocalPlaybackService.progress` for this device. Draw it through VibesDS's `PlaybackTimeline` (redraws once per pixel, only while visible and playing), report positions through `Room.updatePlaybackPosition(_:)` / `noteProgress(_:)` rather than writing them, and move a speaker's position only through `SonosService.seek` / `next` / `previous`, which hold the bar until the speaker lands. Skips are instant and coalesced (`SonosService+TrackSkip.swift`). See `Docs/PlaybackProgress.md`
- **Mac GPU cost**: on the Mac an animated SF Symbol swap or pulse, a `MeshGradient` whose colours change, or an animated swap of the whole player costs ~90 MB of GPU memory for ~2 s each time, so those are off there (`GroupMediaControlsView.animatesPlayPause`, `PlaybackIconView`, `VibeGaugeView`) and the player backdrop is a small CPU-drawn bitmap (`ArtworkMeshBackground`)

### Music Service Integration
- All music services implement common protocols in MusicSearchKit
- Authentication flows are handled per-service
- Search results are normalized to `PlayableContent` models
- Artwork is cached and managed through `ImageCacheService`

### Sonos Integration
- Sonos is opt-in in the iOS/Mac app: `SonosService.isEnabled` (asked in onboarding by `SonosQuestionStep`; changed later in Settings ▸ Sonos ▸ Use Sonos Speakers; while it is off the Play On button is the system AirPlay picker). While it is off, monitoring and group loads never touch the network, so no Local Network prompt appears. Hide speaker-only UI behind `sonosService.isEnabled`, and make sure a play action never ends in the speaker picker while it is off
- The Play On button (`PlaybackRouteButton`) opens `PlayOnSheet`, a sheet that zooms out of the button (`ZoomTransitionSource.playOn`), laid out like the system AirPlay picker: This Device, then every active room, each row its own volume slider (`VolumeRouteRow`); a muted icon draws a slash on and dims with `.tertiary` (on the glass sheet `.opacity` doesn't dim a white icon, and cut-outs are masks, not `destinationOut` blends). While playback is on this device, or still on its way to a speaker (`PlaybackRoute.isSwitching`), each Sonos group is one row (`GroupRow`: what it's playing or has paused, its volume); once playback lands on a group it opens out into its rooms, animated, and the sheet resizes with it. On a speaker, a bar under the list (`GroupBar`) holds Everywhere (a round toggle: groups every room, or Ungroup All once they all are), All Speakers (the group's volume; a long press mutes them all) and Sync (every room to the group's level). Speaker icons that stand for several rooms carry a badge counting them, in the accent with the count cut out. The volume drag ticks once per percent, from the drag itself (`VolumeHaptics`), and a mute Cue sets holds against the poll for a moment (`Room.holdMute`, `GroupRoom.holdMute`). A sideways drag sets that row's volume (rooms and the group through `SpeakerVolumeWriter`, throttled, holding `isEditingVolume`; while one moves the other follows at once, the group as its rooms' average and the rooms in proportion from where a group drag began, and the speaker's own levels replace the estimates after the hold); a tap (the row is a `Button` with `RouteRowButtonStyle`, for its pressed look, keyboard focus and hover; the whole rectangle takes the touch, hit-tested outside the press scale; `SidewaysPan` cancels its touch when a drag begins) routes there, or on a speaker adds or drops the room (`GroupMembership`, shared with the press-and-hold group menu); a long press mutes one room or plays only there (`GroupMembership.playOnly`). The volume drag is `SidewaysPan`, a UIKit pan that only begins sideways, so vertical drags reach the list and the sheet's pull to dismiss untouched (a SwiftUI drag on the rows took every touch and broke it). Each row is its own view reading its own room, so a level change redraws that row, not the sheet. The header sits above the list and the bar below it, neither in it. The sheet opens at a height fitted to its rooms, the sum of the header, rows, bar and bottom inset each measured with `onGeometryChange` (`refit()`), never from its own current size, which mid-presentation is wrong; it opens at the height it last fitted to for that layout (`AppStorageKeys.playOnSheetHeights`) and can be pulled up to `.large`. The list doesn't scroll while its rows fit (`listFits`); with more rooms than the screen holds it scrolls, its foot fading above the bar
- Real-time device discovery and monitoring
- XML parsing for Sonos API responses
- Group management and speaker coordination
- Queue management and playback control

### Testing
- Unit tests for core business logic in packages
- Integration tests for API interactions
- UI tests for critical user flows
- Mock services for testing without real hardware

## Common Tasks

### Adding New Music Service
1. Add API client to `MusicSearchKit/Sources/MusicSearchKit/`
2. Create models in `MusicSearchKit/Sources/MusicSearchKit/Models/`
3. Add authentication service if needed
4. Update `MusicSearchService` to include new service
5. Add UI components in main app

### Modifying Sonos Integration
1. Update `SonosAPI` for new endpoints
2. Add XML parsers if needed in `SonosKit/Sources/SonosKit/Parsers/`
3. Update models in `SonosKit/Sources/SonosKit/Models/`
4. Test with real Sonos hardware

### Adding New Settings
1. Define keys in appropriate `Defaults` package file
2. Add UI in `Preferences/PreferenceScreen.swift`
3. Use `@AppStorage` or `@CloudStorage` as appropriate
4. Update settings screen layout

### Platform-Specific Features
- **iOS**: Focus on mobile-optimized UI. The Lock Screen relies on the system Now Playing card, always on for Cue Super (there is no Lock Screen setting; `NowPlayingSessionService.isPreferenceOn` is fixed to true, and Use iPhone Volume Buttons lives in Settings ▸ Sonos); Live Activities are off for now (`LiveActivityManagerKey` and `LiveActivityManagerFactory` hand out `LiveActivityManagerMock`, `NSSupportsLiveActivities` is unset, and the Widgets extension is not embedded)
- **CarPlay**: `CarPlay/` is an audio-app template scene (Recents, Library, Downloads, Radio) that always plays on the device and has no Sonos UI: a speaker has no place in a car. While a car is connected, `LocalPlaybackService.publishesAppleMusicCard` puts Apple Music on Cue's own Now Playing card too, because on iOS 27 the car's Now Playing screen reads only the app's own card (FB24840951). iOS reads that card as paused (MusicKit makes the sound out of process, and `playbackState` is macOS-only), so the car's clock only moves because the card is restated every second (`restatesClock`), and its play/pause glyph can't be fixed from here. Buttons pinned above a list (`headerGridButtons`) take only a plain `UIImage(systemName:)`: iOS 27 draws no other image there (FB24806621), a recoloured symbol included, while rows use `CarPlayArtwork.symbol` so they aren't black on the car's dark screen. Now Playing's shuffle and repeat buttons only take a tap while `changeShuffleModeCommand` / `changeRepeatModeCommand` are enabled with a target (`LocalNowPlayingPresenter` registers them; the Sonos mirror switches them off for its own card), and the Up Next button gets no `upNextTitle`, so the car draws its queue icon. The entitlement is in `Cue/Cue-iOS.entitlements` (iOS SDKs only; `Cue.entitlements` is shared with Mac/TV/Vision and must not carry it), the scene is in `Cue/Info.plist`, and `AppDelegate.application(_:configurationForConnecting:)` hands that role `CarPlaySceneDelegate`. Test it in the Simulator with I/O ▸ External Displays ▸ CarPlay
- **macOS**: Leverage menu bar app and Mac-specific controls
- **tvOS**: Optimize for remote control navigation
- **watchOS**: A device-first player for Plex and Subsonic, rewritten from scratch (the old Sonos remote and its widgets live in git history). The watch is the client: it browses and searches the servers itself with MusicSearchKit (its home screen, `WatchLibraryBrowser`, `WatchAccounts`), with the sign-ins the iPhone shares (`WatchCredentials`). What's on the watch is a list of picks — albums, playlists, artists and songs by id (`WatchPicks`) — made on either device: browsing on the watch, Add to Apple Watch in a menu on the iPhone (Settings ▸ Storage ▸ Apple Watch lists them). Only the picks cross, as each side's application context (the iPhone's also carries the sign-ins); each side merges what arrives per pick (later of add and removal wins, removals kept as tombstones) and sends back only when the other was missing something. The watch looks each pick up on its server (`WatchLibraryBrowser.songs(for:)`), again when the sign-ins change and every six hours, and `WatchDownloadStore` downloads the songs; `WatchPlayer` plays the files through a long-form audio session (`UIBackgroundModes: audio` — watchOS ignores `WKBackgroundModes` for audio)

### Apple Watch downloads
- watchOS routes a watch app's `URLSession` traffic through the iPhone whenever the two are connected over Bluetooth (tens of KB/s), and no app can choose otherwise. Low-level networking, `NWPathMonitor` included, is off limits outside audio streaming and VoIP (TN3135), so the app can't ask which way a transfer goes.
- Downloads normally run on a background session (`dance.cue.watch.downloads`), 16 songs handed to it at a time, and carry on with Cue closed. **Fast Download** runs them on a foreground session, four at a time, while Cue is open, and asks for Bluetooth to be turned off in the iPhone's Settings app (Control Center leaves the watch connected), which leaves the watch its own Wi‑Fi. The speed is the evidence of the route (`RouteEstimator`: under 250 KB/s after 5 s is "through iPhone", 400 KB/s or more is Wi‑Fi), and the screen asks again while it's slow. Leaving the app hands what's left back to the background session; returning resumes the fast run.
- Each transfer logs its metrics (proxy connection, local and remote address, KB/s) under the `dance.cue.watch` subsystem, for checking the route on a device.
- Only Plex and Subsonic go on the watch: the same rule as `DownloadManager`, since their songs are plain URLs. Adding is gated by `FeatureGate` `.downloads`, with no separate limit.
- Songs go at the watch's own quality (`WatchDownloadQuality`: MP3 at 256/192/128 kbps converted by the server, or Original), not the iPhone's Streaming Quality. The watch asks the first time it has music to fetch and keeps it in its defaults; songs come down at the recommended one meanwhile. MP3 because Plex and Subsonic send Opus in Ogg, which the watch's player can't open. Streams are built when a download starts (`WatchSong.stream(at:)`, `ConvertedStream` in MusicSearchKit), so they carry the current sign-ins; a new quality fetches each song again and plays the old file (`previousFileExtension`) until the new one lands.
- Plex converts as it sends, and starting a transcode can end another of the same client, so the watch's run under client ids of their own (`WatchDownloadStore.plexClients`: `Cue-Watch`, `Cue-Watch-2`), never ending one the iPhone is playing, and as many at once as there are ids. One conversion goes about as fast as the server encodes (around 2 MB/s), so two fill more of Wi‑Fi. A conversion the server breaks off (`cannot parse response`, `bad server response`, connection lost) is tried again twice by itself, then counts as failed; opening Cue, new sign-ins or Fast Download try failed songs again. A lookup that fails part-way (a playlist page, one of an artist's albums) fails whole, so a passing fault never deletes songs.
- Beyond the app: **double tap** (and the pinch, watchOS 11+'s `handGestureShortcut(.primaryAction)`) presses the play button on the right edge of the home screen's bottom bar (play/pause, or Shuffle Downloads when nothing's loaded) and an album's Play. **Siri and Shortcuts** (`Watch/Intents`): `ShuffleDownloadsIntent`, `PlayDownloadsIntent` and `PlayPickIntent` (a `PickEntity` per pick, names refreshed with `CueShortcuts.updateAppShortcutParameters()` when picks change) are `AudioPlaybackIntent`s, so they play in the app. **Widgets** (`WatchWidgets/`): one widget for the Smart Stack and faces (rectangular with a Shuffle button, circular, corner, inline; ranked up while playing or downloading) reading `WatchWidgetState`, which `WidgetStatePublisher` writes a few seconds after the store or player changes and then reloads; tapping opens Downloads or Now Playing (`cuewatch://downloads`, `cuewatch://nowplaying`, handled by `onOpenURL`). A Shuffle Downloads control for Control Center on watchOS 26+. The playback intents file is shared with the extension (a membership exception), where `WIDGET_EXTENSION` compiles `perform` empty; the system runs them in the app.
- The watch's home (`LibraryScreen`) has no title: a Downloads row at the top (the count of songs on the watch in its title) opening `DownloadsScreen` (Fast Download while songs are still to come, then what's on the watch, each with the room it takes), then the lists of the chosen library (playlists, recently added, albums, artists, songs — the same as the iPhone's library screens) under its name. Settings is top left (quality, storage, Remove All, which sign-ins arrived), the library picker top right (an icon; Plex or Subsonic). The bottom bar holds search (`TextFieldLink`, left), Now Playing (the system's animated waveform, centre) and play (right); it hides while the list scrolls down and comes back scrolling up or at the top (`onScrollGeometryChange` driving `.toolbar(.hidden, for: .bottomBar)`, watchOS 11). watchOS 27's `toolbarMinimizationBehavior` only takes `.automatic` on the watch (`.onScrollDown` is iOS-only), hence the hand-rolled version. Screens zoom out of the row or button that opened them (watchOS 11 `navigationTransition(.zoom)`): the routes are the ids, and the home screen's namespace reaches rows further in through `\.zoomNamespace`. The player hands Now Playing the song's cover (`ArtworkStore`, prefetched when a pick is looked up, so it shows offline); a Plex song without its own cover uses its album's (`parentThumb`). A song goes on with a tap, an album or playlist opens on its songs to add whole or one at a time, an artist on its albums. 40 rows a page, with no iPhone in reach. Keys match the iPhone's download manager (`WatchKeys`), so a pick made on either device is the same pick. MusicKit has no player on watchOS (`ApplicationMusicPlayer` and `SystemMusicPlayer` aren't available there), so Apple Music stays out.

## Deferred Work / Notes

### Song preview in the queue (on hold)
Idea: bring the song-preview feature (30s clip, progress fill, tap-to-stop)
to the queue screens, matching the search rows. Implemented and then reverted
(revert kept on branch `claude/song-preview-feature-unrgql`) — hold for later.

Key findings for whoever picks this up:
- Queue artwork does **not** carry a preview URL. It is the Sonos speaker's
  own image (`http://<speaker-IP>:1400/...`) via `ArtworkManager` (Nuke image
  pipeline only) — there is no Apple Music fetch in that path.
- Queue items parsed by `QueueParse.swift` already carry a `service` and a
  catalog track ID in `content.id` (for Apple, the numeric `song:<ID>`), so
  previews can be enriched by ID without re-fetching tracks.
- Approach used: `MusicSearchService.enrichWithPreviews([PlayableContent])` —
  batch `MusicCatalogResourceRequest<Song>` keyed off `content.id`, chunked at
  100 to respect the API id cap; call it after each `getQueue` in
  `QueueScreen.scrollToNowPlaying` and `UpNextContentView.loadUpNext` /
  `loadMoreTracks` (`MusicSearchService.shared` is already in the environment
  via `.withEnvironments()`).
- UI parity lives in `QueueCellView` (own cell, not the shared
  `PlayableContentView`): progress-fill background, tap-to-stop on the cell,
  stable disabled-Menu + overlay stop icon, leading swipe Preview action,
  `contextMenu(preview:)` with `SongPreviewCard`, and `SongPreviewButton` in
  the ellipsis menu.
- Scope decided: Apple Music only first (Spotify/Deezer would each need their
  own preview-URL lookup path).

### Monetization notes
- Downloads (Plex/Subsonic, `DownloadManager`) are free up to
  `DownloadManager.freeSongLimit` songs held at a time; Cue Super lifts the
  cap. The gate lives in the manager (`download(_:)` returns `false`,
  `download(contentsOf:)` returns a `BatchResult`), with the meter in
  `DownloadsScreen` and the "This Device" menu.
- Super Day (a free 24-hour pass to Super, once a month) is designed but not
  built — see `Ideas/super-day.md`. It needs the `SubscriptionService`
  activity check moved to `entitlements.active` first.
