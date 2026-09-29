# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cue is a multi-platform SwiftUI music player that also controls Sonos speakers. It plays Apple Music, Plex, Subsonic, TuneIn and local files on the device itself (`LocalPlaybackService`) and hands the same queue to a Sonos group (`PlaybackRoute`). It provides native apps for iOS, iPadOS, macOS, tvOS, watchOS, and includes widgets, live activities, and a menu bar app (Cue Mini).

## Product Priorities

1. **Best music player first.** Cue is a player that happens to be an excellent Sonos client, not a Sonos remote with a player bolted on. Playback, queue, library, search and Now Playing must be complete on the device alone, with no speaker on the network.
2. **Best Sonos client second.** Everything the device can play must also play on a Sonos group, and the hand-off between the two must be seamless (`PlaybackRoute`).
3. **Every service must play on the device and on Sonos.** A service belongs in Cue only if its audio can be played by the device (MusicKit, a direct stream URL, or a local file) *and* by a speaker. Services whose audio only a speaker can reach are not supported, however popular they are on Sonos. Today that rule excludes Spotify, Tidal, Deezer, SoundCloud, Pandora, Sonos Radio and the speaker's own Music Library. See `Ideas/device-first-services.md` for the audit and the removal plan.

When a change forces a trade-off between the player and the Sonos client, the player wins. Do not add a service, feature or screen that only works when a speaker is present.

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

### Main App Structure
- **CueApp.swift** - Main app entry point with shared services
- **Router.swift** - Navigation and routing system
- **Services/** - Core app services (ImageCache, Queue, PlayHistory)
- **Search/** - Search functionality across music services
- **Library/** - Music library browsing and management
- **Routing/** - App navigation and destination management

### Platform-Specific Apps
- **CueMini/** - macOS menu bar app for quick controls
- **Watch/** - watchOS app with simplified controls
- **TV/** - tvOS app optimized for Apple TV
- **Widgets/** - iOS/macOS widgets and live activities
- **PlayAction/** - Share sheet extension for queuing music

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
- **iOS**: Focus on mobile-optimized UI and live activities
- **macOS**: Leverage menu bar app and Mac-specific controls
- **tvOS**: Optimize for remote control navigation
- **watchOS**: Keep UI minimal and focused on essential controls

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

### Single window
Cue runs in one window (`UIApplicationSupportsMultipleScenes` is `false` in
`Cue/Info.plist`). App-wide state such as `Router.main` — including the player
cover's `isPlayerPresented` — assumes that. If multiple windows come back,
presentation state has to move per window (a `Router` per scene, or
`@SceneStorage`), with the menu commands acting on the key window.

### Monetization notes
- Downloads (Plex/Subsonic, `DownloadManager`) are free up to
  `DownloadManager.freeSongLimit` songs held at a time; Cue Super lifts the
  cap. The gate lives in the manager (`download(_:)` returns `false`,
  `download(contentsOf:)` returns a `BatchResult`), with the meter in
  `DownloadsScreen` and the "This Device" menu.
- Super Day (a free 24-hour pass to Super, once a month) is designed but not
  built — see `Ideas/super-day.md`. It needs the `SubscriptionService`
  activity check moved to `entitlements.active` first.
