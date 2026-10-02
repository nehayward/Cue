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
- Other targets (Mac, TV, Cue Mini) build with `xcodebuild` as usual; only the iOS app is deployed.

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

2. **MusicSearchKit** - Music service integrations
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
   - `WatchLibrary`/`WatchTrack`/`WatchCollection` (what's on the watch), `WatchStatus` (what the watch reports back), `WatchSyncMessage` (WatchConnectivity keys), `WatchSyncPlan`
   - `TransferRateMeter` and `RouteEstimator`, which tell the watch's own Wi‑Fi from the iPhone relay by speed

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
- **Watch/** - watchOS app (`Cue (Watch)`, embedded in the iOS app): plays Plex and Subsonic songs downloaded to the watch. See Apple Watch below
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

### Music Service Integration
- All music services implement common protocols in MusicSearchKit
- Authentication flows are handled per-service
- Search results are normalized to `PlayableContent` models
- Artwork is cached and managed through `ImageCacheService`

### Sonos Integration
- Sonos is opt-in in the iOS/Mac app: `SonosService.isEnabled` (asked in onboarding by `SonosQuestionStep`; changed later in Settings ▸ Sonos ▸ Use Sonos Speakers; while it is off the Play On button is the system AirPlay picker). While it is off, monitoring and group loads never touch the network, so no Local Network prompt appears. Hide speaker-only UI behind `sonosService.isEnabled`, and make sure a play action never ends in the speaker picker while it is off
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
- **macOS**: Leverage menu bar app and Mac-specific controls
- **tvOS**: Optimize for remote control navigation
- **watchOS**: A device-first player for Plex and Subsonic, rewritten from scratch (the old Sonos remote and its widgets live in git history). What's on the watch is chosen on the iPhone (Add to Apple Watch in a song, album, playlist or artist menu; Settings ▸ Storage ▸ Apple Watch lists it). `WatchSyncService` (iOS) keeps the `WatchLibrary` and sends it whole as application context, LZFSE-packed, falling back to `WCSession.transferFile` past 48 KB (file transfers never arrive between simulators, so a library that big only syncs on devices); the watch's `WatchDownloadStore` downloads the self-authenticating stream URLs straight from the server and answers with a `WatchStatus` as application context. `WatchPlayer` plays the files through a long-form audio session (`UIBackgroundModes: audio` — watchOS ignores `WKBackgroundModes` for audio)

### Apple Watch downloads
- watchOS routes a watch app's `URLSession` traffic through the iPhone whenever the two are connected over Bluetooth (tens of KB/s), and no app can choose otherwise. Low-level networking, `NWPathMonitor` included, is off limits outside audio streaming and VoIP (TN3135), so the app can't ask which way a transfer goes.
- Downloads normally run on a background session (`dance.cue.watch.downloads`), 16 songs handed to it at a time, and carry on with Cue closed. **Fast Download** runs them on a foreground session, four at a time, while Cue is open, and asks for Bluetooth to be turned off in the iPhone's Settings app (Control Center leaves the watch connected), which leaves the watch its own Wi‑Fi. The speed is the evidence of the route (`RouteEstimator`: under 250 KB/s after 5 s is "through iPhone", 400 KB/s or more is Wi‑Fi), and the screen asks again while it's slow. Leaving the app hands what's left back to the background session; returning resumes the fast run.
- Each transfer logs its metrics (proxy connection, local and remote address, KB/s) under the `dance.cue.watch` subsystem, for checking the route on a device.
- Only Plex and Subsonic go on the watch: the same rule as `DownloadManager`, since their songs are plain URLs. Adding is gated by `FeatureGate` `.downloads`, with no separate limit.

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
