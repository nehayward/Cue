# Changelog

Developer-facing record of changes per version. More detailed than ReleaseNotes.md — includes the what and why, not just the what. Use this as source material when writing App Store release notes.

---

## 2026.5

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

### Mac Dock menu reorder
- `DockMenuRenderer.populate` reordered so the least-used controls are at the top and transport is at the bottom (closest to the Dock icon, where the cursor already is)
- New order: Sleep Timer → Playback section header (Repeat / Shuffle / Crossfade inline) → Volume → Speaker switcher → Now Playing + Favorite → Transport
- Repeat / Shuffle / Crossfade previously had no section label; now preceded by a disabled "Playback" header instead of a submenu
- Favorite moved from its own separator-bounded section into the Now Playing group, directly below the track line

---
