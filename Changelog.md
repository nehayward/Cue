# Changelog

Developer-facing record of changes per version. More detailed than ReleaseNotes.md — includes the what and why, not just the what. Use this as source material when writing App Store release notes.

---

## 2026.5

### Song previews in the context menu
- Long-press an Apple Music or Spotify track and the preview clip starts playing automatically (`onAppear`), so you can quickly audition songs one after another
- The preview keeps playing after the menu is dismissed and only stops when the user taps the option again — the label toggles between Preview Song / Stop Preview, and tapping never dismisses the menu (`menuActionDismissBehavior(.disabled)`)
- Opening another track's menu swaps the preview to that track; `preview(url:)` is a no-op if the same clip is already playing
- Preview audio runs through `AudioPlaybackService.preview(url:)` using a mixed, ambient `AVAudioSession` (`.ambient` + `.mixWithOthers`) so it layers over other audio and respects the silent switch — distinct from the ducking `.playback` session used by `play(url:)`
- Only shown for tracks that actually carry a `previewURL` (mapped from Apple Music `previewAssets` and Spotify `previewUrl`)

### ClicAction extension ("Listen with Clic")
- New `com.apple.ui-services` Action extension that appears in the Actions row of the share sheet (separate from PlayAction which sits in the Share row)
- Display name: "Listen with Clic"; bundle ID `$(BUNDLE_ID).ClicAction`
- Shares `QueueListView.swift`, `ActionViewController.swift`, and `PlayHistoryService.swift` from the PlayAction folder via `PBXFileSystemSynchronizedRootGroup` + exclusion sets — no file duplication
- Embedded in both Clic iOS and Clic Mac targets

### Share sheet queue position selector
- `QueuePosition` picker added to the content header (hidden for radio content)
- Pre-selects `.replace` for playlists, `.now` for everything else when content loads
- Options: Now / Next / Last / Replace (Front excluded as irrelevant for the share context)
- Both `performPlay` and `playInGroup` now use the `queuePosition` state instead of hardcoded logic

### Share sheet UI refinements
- Room subtitle shows current track name if playing, grouped info ("Grouped with Kitchen +2") if in a multi-room group but nothing playing, or "—" if idle and ungrouped
- Volume button replaced with a capsule `Label("Volume", …)` using small caps so its function is self-evident
- Content header card uses `.glassEffect(.regular.interactive())` on iOS 26; falls back to `.thinMaterial` on earlier OS

### Apple Music artwork quality fixes
- `ITunesLookupItem.artworkURL(size:)` now requests `cc` (crop-center) format instead of `bb` (background letterbox) — eliminates white padding on album/playlist artwork throughout the app
- `AppleMusicOpenGraphAPI` rewrites the landscape `og:image` social-card URL (1200×630) to a square 600×600cc crop from Apple's CDN before storing it in `PlayableContent.artwork` — fixes blurry/cropped artwork in the share sheet for editorial playlists

### Hardware volume buttons (iOS)
- `HardwareVolumeService` intercepts hardware button presses via AVAudioSession KVO on `outputVolume`; translates deltas into `setRelativeGroupVolume` calls on the active Sonos group
- `MPVolumeView` kept in the SwiftUI hierarchy (1×1, alpha 0.0001) to suppress the system volume HUD
- Volume parked at midpoint (0.5) only when near an extreme (≤0.15 or ≥0.85) to avoid unnecessary system volume changes; original volume restored on `stop()`
- Pauses listening when app backgrounds, resumes on foreground via `AsyncStream<AppEvent>`
- Toggle added to Playback section in preferences (`AppStorageKeys.useHardwareVolumeButtons`); modifier applied on the player screen via `.hardwareVolumeControl(group:)`

### Spotify album saving
- Added `saveAlbum`, `deleteAlbum`, `isAlbumSaved` to `SpotifyAPI` (`PUT/DELETE/GET /v1/me/albums`)
- Added `saveSpotifyAlbum`, `deleteSpotifyAlbum`, `isSpotifyAlbumSaved` wrappers to `MusicSearchService`
- `FavoriteMenuButton` now routes `.album`/`.libraryAlbum` content to album endpoints for Spotify; tracks fall through to the existing track endpoints
- Works from search results, album detail page (`MediaDetailView` → `PlayableMenuView`), and anywhere else `FavoriteMenuButton` appears

### Apple Music album favoriting
- Added `updateAlbumFavoriteStatus(albumId:favorite:)` and `isAlbumFavorite(albumId:)` to `AppleMusicAPI`
- Uses `PUT/DELETE /v1/me/ratings/albums/{id}` (same rating system as songs)
- Adds album to library first (`POST /v1/me/library?ids[albums]=`) before rating — required for the rating to persist (same pattern as songs)
- `FavoriteMenuButton` routes `.album`/`.libraryAlbum` for Apple Music to these new methods

### Spotify artist following (removed)
- Explored `PUT/DELETE /v1/me/following?type=artist` — returns 403 Insufficient client scope
- App does not request `user-follow-modify` OAuth scope; would require user re-auth to add
- Feature removed; artist follow button not shown anywhere

### MusicService cross-version decode resilience
- `MusicService` (plain Codable enum, no RawValue) is synthesized as a single-key keyed container (`{"caseName":{}}`). When a case is added in one app version (e.g. `deezer`) and removed in a later one, iCloud-stored play history or queue data containing that case caused a decode failure: `allKeys` returned 0 known keys → "Invalid number of keys found, expected one" → crash via `assertionFailure` in `CloudStorage+Codable.swift`
- Added a custom `init(from:)` to `MusicService` in both `SonosKit` and `SonosKitMini` using a dynamic `CodingKey` struct so any unrecognized case key falls back to `.unknown` instead of throwing
- Synthesized `encode(to:)` is unchanged — existing stored data remains compatible

### QueueManager cleanup
- `addToQueue(item:)` now delegates to `add(items:)` to eliminate duplicated continuation/Task logic
- `add(items:)` yields all items then fires a single `Task { @MainActor in }` for the last non-banner item, down from one Task per item
- `playFolder()` replaced its per-item `addToQueue` loop with a single `add(items:)` call over a mapped array; first playlist gets `.replace`, subsequent ones get `.end`, fixing the folder queue behavior end-to-end
- `QueueManager` marked `@Observable` so `isProcessing` and `lastQueuedItem` are trackable by SwiftUI
- `playSong` marked `@MainActor` (matches its `@MainActor` caller `processQueue`); inner `Task { @MainActor in }` for play history update removed
- `handleError` made `async`; `sonosService.services()` awaited directly instead of inside a nested unstructured `Task`
- Deleted ~50 lines of commented-out dead code

### Last.fm popular tracks + remote feature flags

#### Popular tracks (Plex + library artists)
- `LastFMAPI` added to `MusicSearchKit` — calls `artist.gettoptracks` (limit 50, HTTP-cached via `Cache-Control: max-age=3600`)
- `PopularTracksService` added to the app layer; owns `LastFMAPI`, title normalisation, and two focused methods: `matchLastFM(artistName:songs:)` and `matchAppleMusic(artistName:songs:)`
- Title normalisation strips parentheticals, brackets, dash-suffixed keywords (remaster/live/remix etc.), and bare `feat.`/`featuring`; prefers shorter title when two songs normalise to the same key (avoids returning a remix over the original); prefix-word fallback catches trailing variants not handled by stripping
- `MusicSearchService` no longer knows about Last.fm or flag state; `lookupPlexArtistTopTracks` replaced by `lookupPlexTracks(id:)` — returns raw viewCount-sorted Plex tracks only
- `ArtistDetailView` orchestrates: checks `RemoteFeatureFlags.isEnabled(.lastFM)` before calling Last.fm; library artists fall back to Apple Music `topSongs` when Last.fm is off or returns no matches; Plex artists show no popular tracks section when flag is off
- "Powered by Audioscrobbler" row added to Preferences → About

#### Remote feature flags
- `RemoteFeatureFlags` — `@Observable` singleton, fetches `https://api.clic.dance/flags` on launch; decodes `[String: RemoteFlag]` (fields: `enabled`, `minVersion`); merges into a `Set<Flag>` rather than replacing (omitted flags keep their prior state)
- `minVersion` check uses `.numeric` string comparison so "2.10" > "2.9" is handled correctly
- `DEBUG` builds skip the fetch and default all flags to enabled; `Release` starts with all flags off
- `BetaFeatures.swift` deleted (was dead code — only reference was commented-out Tidal toggle)
- `RemoteFeatureFlags` injected into the environment via `AppRegistry`; consumed in `ArtistDetailView` via `@Environment(RemoteFeatureFlags.self)`
- Cloudflare Worker at `api.clic.dance/flags` — plain JS, no dependencies, single `FLAGS` object to edit and `npx wrangler deploy`

### Start Live Activity shortcut and Control Center widget
- `CreateLiveActivityIntent` renamed from "Create" to "Start Live Activity", made discoverable, given a `description` and `parameterSummary`
- `perform()` now uses `$room.requestValue()` when room is nil (Shortcuts flow without a pre-configured speaker) instead of throwing; room is resolved to `coordinatorID` via `getGroupCoordinatorWithRoom` so grouped speakers are handled correctly
- `AppShortcut` registered in `ClicAppShortcutProvider` with phrases "Start live activity in Clic" and "Start [speaker] live activity in Clic"
- `StartLiveActivityControlWidget` added (iOS 18+) — `AppIntentControlConfiguration` wrapping `CreateLiveActivityIntent`, shows configured speaker name on the button, registered in `WidgetBundle`

### MiniPlayer TV mode controls
- `MiniPlayerView` body restored to the original single `#if !targetEnvironment(macCatalyst) && !os(visionOS)` guard — no tvOS platform splits
- `groupInfoButton` label now contains a `ZStack` that crossfades between the normal layout (track marquee + play/pause + next) and the TV mode layout (audio input format + TV controls) via `opacity` driven by `group.TVMode`
- `artworkView` is itself a `ZStack`: `ContentArtworkView` fades out and a hierarchical `"tv"` SF Symbol fades in when `TVMode` is true — matching the treatment in `TVPlayerView`
- `tvInputInfoView` shows `group.nameWithCount` (caption2) and `group.tvSettings?.audioInputFormat.description` (semibold) in place of the song/artist marquee
- `MiniTVControlsView` (private struct) renders night mode (`moon.zzz.fill`), mute (`speaker[.slash].fill`), and speech enhancement (`person.wave.2.fill`) as `.bordered` buttons; `.controlSize(.small)` on the HStack keeps them the same scale as the existing playback buttons; mute inlined to avoid `MuteButton`'s hardcoded 40×36 frame

### Mac Dock menu reorder
- `DockMenuRenderer.populate` reordered so the least-used controls are at the top and transport is at the bottom (closest to the Dock icon, where the cursor already is)
- New order: Sleep Timer → Playback section header (Repeat / Shuffle / Crossfade inline) → Volume → Speaker switcher → Now Playing + Favorite → Transport
- Repeat / Shuffle / Crossfade previously had no section label; now preceded by a disabled "Playback" header instead of a submenu
- Favorite moved from its own separator-bounded section into the Now Playing group, directly below the track line

### Spotify same-album artwork flicker fix
- Root cause: three compounding issues caused artwork to flash when skipping between Spotify tracks on the same album
- **Double URL churn** — `SonosService` assigns the new `Track` from Sonos XML immediately (before the CDN URL arrives), resetting `downloadedArtworkURL` to nil. This caused `ArtworkView`'s `.task(id: artworkURL)` to fire twice: once for the Sonos proxy URL and once for the Spotify CDN URL. The Sonos proxy is unreliable at track boundaries, so the first fire often fails → grey placeholder flash
- **Unstable Nuke cache key** — `imageIDKey` in `ArtworkView` was keyed on `album + artist`. Sonos sends `dc:creator` (per-track artist) for Spotify, not `r:albumArtist`. On featured tracks the artist string varies between songs, so the cache lookup missed even though the album art is identical
- **Error handler blanked artwork** — `ArtworkView` nil'd `currentImage` on any failed image load, guaranteeing a visible blank frame on Sonos proxy failures
- **Fix 1 (SonosService, two sites):** when `awaitedTrack.album == currentTrack.album` and `!awaitedTrack.album.isEmpty` and a prior `downloadedArtworkURL` exists, carry that URL into `awaitedTrack` before the early assignment. `artworkURL` never changes during a same-album skip, so `.task` never refires at all. The CDN URL from `getTrackInformation` still overwrites when it arrives, but it's a no-op (same URL for same album)
- **Fix 2 (ArtworkView.imageIDKey):** simplified to `album.service.player` for all services — Spotify same-album tracks share one cache entry regardless of featured-artist variation in `dc:creator`; including `service` prevents cross-service collisions (e.g. a Plex album with the same name as a Spotify album)
- **Fix 3 (ArtworkView error handler):** swallow load errors silently instead of nil-ing `currentImage`; the `guard let artworkRequest else { currentImage = nil }` path still clears artwork when the track genuinely has no URL

---
