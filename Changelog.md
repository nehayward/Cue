# Changelog

Developer-facing record of changes per version. More detailed than ReleaseNotes.md — includes the what and why, not just the what. Use this as source material when writing App Store release notes.

---

## 2026.6

### Playlist management across music services
First-class playlist management for Apple Music, Spotify, Plex, and Deezer alongside Sonos.

**Add to playlist**
- New `AddToPlaylistSheet` (replaces the old single-track Sonos `AddToPlaylistMenu`): share-sheet-style, segmented between the track's own service and Sonos, with multi-select + one Done, search, a "New Playlist" action, a "Recently Added" quick-pick (top 3), and a confirmation toast that deep-links to the target playlist
- Wired into every track-menu surface: `PlayableMenuView` (search/library/detail), `MenuInfoView` (Large Player), the queue menus (`QueueCellView`/`QueueScreen`/`UpNextContentView`), and the macOS native `UIMenu` (now lists the track's service playlists + Sonos)
- One-tap "Add to last playlist" shortcut (`AddToLastPlaylistButton`) with the destination service icon, gated to service-compatible tracks; last-used playlist (id/title/service) and recents tracked centrally in `LastPlaylist`
- `MusicSearchService` gains create/add/remove/delete wrappers + service-agnostic dispatch (`addToServicePlaylist`/`removeFromServicePlaylist`/`reorderServicePlaylist`); `SpotifyAPI`/`PlexAPI`/`DeezerAPI`/`AppleMusicAPI` gain the underlying mutation endpoints

**Edit playlists** (`MediaDetailView` + `PlaylistEditCoordinator`)
- Swipe-, menu-, and bulk-remove; drag-to-reorder; delete playlist — all optimistic with rollback on failure. Sonos and streaming edits both route through `PlaylistEditCoordinator`, which owns the track list so edits survive view rebuilds
- Undo/Redo for add/remove via an owned undo/redo stack on the coordinator (replaces `UndoManager`): one stack drives the tap-to-undo toast, the iOS ⌘Z / ⌘⇧Z keyboard shortcuts, and a native Catalyst Edit ▸ Undo/Redo menu. Sonos edits aren't undoable (its add appends — no positional re-add)
- Editing gated to playlists the user can actually modify: Spotify via owner/collaborative from a `fields`-filtered `/playlists/{id}` lookup (cached user id + membership fallback); Deezer via per-playlist owner check; Plex always (server-owned); Apple never

**Create playlists**
- Create playlists per service from the browse screens ("+") and the add sheet, including **empty** playlists for Apple, Spotify, Deezer, Plex, and Sonos. Plex empty creation posts `type=audio` with no seed (with a title-based fallback when the create response omits the new id)
- `DeletePlaylistConfirmationView` and `NewPlaylistView` follow the app's sheet pattern — top ✕ dismiss, single prominent action button

**Service coverage:** Sonos (full); Spotify / Plex / Deezer (add, remove, reorder, delete, create); Apple Music (add + create only — no public remove/reorder API). Deezer reorder is intentionally excluded (its reorder endpoint takes a full track-id list, unsafe for a paginated playlist); Deezer writes require the `manage_library` OAuth scope.

**Catalyst menu**
- Native Edit ▸ Undo/Redo wired to the playlist editor through the app delegate / responder chain (`PlaylistUndoMenuBridge`); enable/disable follows the undo stack via `canPerformAction`
- Removed the auto-injected AutoFill / Start Dictation / Emoji & Symbols items from the Edit menu (`NSDisabledDictationMenuItem` / `NSDisabledCharacterPaletteMenuItem` + `.autoFill` builder removal)

**Fixes**
- Removing a track from a Spotify playlist now deletes only the selected occurrence, not every copy. The remove request now sends the track's playlist position (`positions`) instead of just its URI, which Spotify treats as "remove all occurrences." Multi-select removals run sequentially (highest position first) so the positional indices stay valid. Plex was already safe (unique per-row id); Deezer's API only removes by track id, so a duplicated Deezer track still removes all copies (upstream limitation).
- Adding a Spotify album with more than 50 tracks now adds the whole album. `addToSpotifyPlaylist` pages through the album's tracks (50 per page) instead of taking only the first page, and posts them in chunks of 100 (the add-tracks request cap) — previously the overflow was silently dropped while still reporting success.
- "Recently Added" in the Add-to-Playlist sheet is now keyed by service (`<service>:<id>`), matching the selection logic, so a recent id from one service can no longer surface a same-id playlist in the other segment.
- Deezer "Add to Playlist" now lists only playlists you own. `userPlaylists(for: .deezer)` filters `/user/me/playlists` to `creator == me` (new `deezerEditablePlaylists()`), mirroring Spotify — previously followed playlists were offered as targets and the add silently failed. Browse still shows all playlists.
- Service playlist browse grids gain a toolbar refresh button (`PlayableGridScreen`), so creates/deletes can be pulled in on Mac/Catalyst where SwiftUI pull-to-refresh doesn't fire.
- `PlaylistEditCoordinator`'s undo/redo history is extracted into a pure, unit-tested `UndoRedoStack` (SonosKit) covering push/undo/redo, redo invalidation on a fresh edit, and clearing.

### Queue shuffle animation
- Tapping the shuffle button in the queue now animates the Up Next and Full Queue lists reordering into their shuffled positions instead of snapping. Move and delete also animate as a side effect.
- Reworked queue row identity: rows are now keyed by `content.id` + *occurrence index* (the Nth copy of a song in the loaded window) via `keyedByOccurrence()`, instead of `trackID` (`content.id` + position). Occurrence keys are unique (handles duplicate songs) and stable under reorder, so SwiftUI animates rows *moving* rather than cross-fading. The shuffle action is now just an animated `withAnimation` swap of the fetched order — no identity-preserving workaround needed.
- List selection, context menus, and delete now resolve the selected occurrence keys back to tracks (`tracks(forKeys:)`); scroll-to-now-playing resolves the row's occurrence key (`occurrenceKey(forPosition:)`) since `ScrollViewReader` matches `ForEach` identity.
- Shuffle/repeat state (`group.playMode`) is now loaded in `onAppear` for both queue modes; previously it was only fetched in the full-queue view's task, so the shuffle/repeat buttons didn't reflect the speaker state when opening the default Up Next view. Their active color is also now driven via `.tint` on the button (iOS toolbars override `.foregroundStyle` on the label with the bar tint, so the highlight didn't show on iOS).
- Now-playing row highlight now compares queue position via a shared `GroupRoom.isNowPlaying(_:)` (gated on playing from the queue) instead of `currentTrackID`. `currentTrackID` was only populated in full-queue code paths, so the playing track never highlighted in the default Up Next view; the position check works in both modes and live-updates as the track changes. Both the row number and the cell use the one helper so they can't drift. The first-load scroll sentinel is now a plain `hasScrolledToNowPlaying` flag (the old `currentTrackID` string value was never read).
- No-op when the returned order is unchanged, so there's no regression for sources that don't reorder `Q:0`.

### Deezer integration
- Added `DeezerAPI` client in `MusicSearchKit` — no auth required, hits public `api.deezer.com` endpoints
- Full search: tracks, albums, artists, playlists (concurrent `async let` in `MusicSearchService.searchDeezer`)
- Browse screen (`DeezerBrowseScreen`) powered by `DeezerBrowseService` showing Top Tracks, Albums, Artists, and Playlists from Deezer charts
- Correct Sonos URIs verified via SOAP capture:
  - Track: `x-sonos-http:tr-flac%3A{id}?sid=2&flags=32`
  - Album: `x-rincon-cpcontainer:0004006calbum-{id}`
  - Playlist: `x-rincon-cpcontainer:0006006cplaylist_spotify%3Aplaylist-{id}`
  - Radio/Mix: `x-sonosapi-radio:radio-track-{id}?sid=2&flags=8300`, title prefixed "Mix {title}"
- Deezer service token auto-detected and stored from Sonos server discovery in `ServicePreferenceScreen`; token read from `GroupStorageKeys.deezerMusicTokenID` at enqueue time
- `MusicServiceParser`: service IDs "2", "519", "250" → `.deezer`; `playlist_spotify` URI check ordered before generic `spotify` check to avoid misidentification
- `SonosServiceType.deezer` added to `MediaServer.swift`; `CoreFeatures.syncEnabledServices` maps `.deezer → .deezer`; included in `preferredDefaultService` fallback chain
- View Album, View Artist, Open in Deezer, and Play Radio (Mix) all wired up — radio available from track context menu, artist page, and large player
- `SonosAPI+MusicServices`: parses `deezer.com/{locale}/{type}/{id}` share URLs, strips 2-letter locale prefix
- `DeezerLinkResolver` (`MusicSearchKit`): resolves the Deezer *app's* short "smart" links — `link.deezer.com/s/{token}` (Branch.io) and legacy `deezer.page.link` / `dzr.page.link` (Firebase) — which carry no type/id in the path. Follows the redirect with a desktop User-Agent, then scans the final URL / interstitial HTML for the canonical `deezer.com/{type}/{id}` link. Wired into `SonosService.getContent(from:)`, so sharing from the Deezer app (not just the website) now works in PlayAction and everywhere else
- Added `Docs/AddingMusicService.md` — comprehensive guide and checklist for integrating future services

### Song previews
- The Apple Music / Spotify track menu gets a "Preview Song" action that plays the clip while the menu stays open (`menuActionDismissBehavior(.disabled)`); a leading-swipe "Preview" action on list rows is the other entry point
- Preview audio runs through `AudioPlaybackService.preview(url:)` using `.ambient` + `.mixWithOthers` so it layers over other audio and respects the silent switch; an explicit call always (re)starts the clip from the beginning, so a track can be re-previewed after it's already played
- `PlayableContentView` (list rows) and `PlayableContentRowView` (browse grids) show a bottom progress bar that fills as the clip plays plus a stop affordance — tapping an auditioning row/cell stops it. The bar is gated on `isPreviewing` so stopping removes it instantly instead of animating its width back to zero
- Only shown for tracks that actually carry a `previewURL` (mapped from Apple Music `previewAssets` and Spotify `previewUrl`)
- Dropped the auto-preview-on-menu-open behaviour and its `AppStorageKeys.autoPreviewSongs` setting. SwiftUI exposes no reliable "menu was presented" signal, so every trigger we tried (`onAppear`, `.id(UUID())`, `.task(id:)`) either missed presentations or re-fired on re-render and replayed the clip right after the user stopped it. Preview is now driven entirely by the explicit button + swipe; also removed the unused `SongPreviewCard` peek view
- Previews now play through `.playback` + `.duckOthers` (was `.ambient` + `.mixWithOthers`), so a deliberate preview tap is audible even with the silent switch on — matching Apple Music. Previews also stop automatically when the app is backgrounded
- Plex previews: Plex has no short clip, so a Plex preview streams the full track from the user's server via a token-authenticated stream URL (built from the media part key), played progressively with `AVPlayer` (`preview(url:streaming:)`) rather than downloading the whole file first
- Tapping a cell to stop an auditioning preview now fires a `buttonPress` haptic
- Apple **library** track previews: library songs and library-playlist/album tracks now preview too. Apple's library API omits previews (a catalog-only attribute), so the library song / playlist-tracks / album-tracks requests now pass `include=catalog` and read the catalog relationship's `previews` into `AppleLibraryItem.previewURL` — one request, no extra round-trips

> **Note — `include=catalog` is a reusable unlock.** Pulling each library item's full catalog resource inline (no per-item lookups) opens up a lot of future potential beyond previews. Any catalog-only attribute — full/animated artwork, genres, ISRC, editorial notes, audio variants (lossless / Dolby Atmos), popularity, accurate release dates — and any catalog relationship (artists, albums) can now be surfaced for **library** content the same way: add the field to `AppleLibraryItem.Attributes` (or a relationship) and read it off the included `catalog`. Worth reaching for whenever a library screen needs richer data than the library API returns.

### Line-in support detection
- `Room.supportsLineIn` now prefers the device-reported `LINE_IN` capability from the `/info` endpoint (`DeviceInfo.capabilities`) instead of relying solely on model-name matching — authoritative across firmware/models
- Tightened the fallback model keywords used when capabilities aren't reported: the bare `"Play"` substring matched Play:1/Play:3/Playbar/Playbase (no line-in), wrongly surfacing the "Switch to Line In" action in `MenuInfoView`
- `"Play:5"` kept; the 2026 portable "Play" matched by exact last-token comparison so its siblings are excluded
- `"Era"` left broad (Era 100/100 SL/300 all support line-in via the USB-C adapter); `"Move 2"`, `"Five"`, `"Amp"`, `"Connect"`, `"Port"` unchanged

### Sonos library pagination
- Library browse lists made a single fixed-size `Browse` request and relied on a one-shot `.task`-fired indicator that never re-triggered, so libraries larger than one page were silently truncated — Albums stopped ~mid-"D" (first 500); Artists only looked complete because there were fewer than 500
- `LibraryBrowseService.updateSongs` / `updateAlbum` / `updateArtists` / `updateGenres` now fetch one page at `offset` and return whether a full page came back (`count >= pageSize`); callers request the next page at `offset == current count`, deduped via `updateOrAppend`. All `update*` methods are `@MainActor` so observed-state writes stay on the main actor
- `PlayableContentList`: replaced the one-shot `.task` load-more indicator with an `.onAppear` sentinel gated by a single in-flight `isLoading` flag plus `hasMoreContent`, so pages load as the user nears the bottom without racing the initial load; a bottom spinner shows only while a next page is actively fetching
- `GenreListView`: added a guarded near-the-end paging trigger (`isLoadingMore` / `hasMoreGenres`); `FolderBrowseView`: added offset paging for Sonos folder contents via `browseFolder(folderID:offset:)`, Apple Music folders keep their single-request path
- `LibraryBrowseScreen`: Imported Playlists load-more closure now forwards `offset` to `updateImportedPlaylists(offset:)` instead of discarding it (was always re-fetching page 0)
- Alphabetical grouping moved out of `PlayableContentList` (where a computed dictionary was re-grouped once per section header and again per letter subscript — O(letters × items) every render) into cached `LibrarySection` arrays on `LibraryBrowseService` (`albumSections` / `artistSections` / `playlistSections`), recomputed only when the underlying set changes; the view now renders the prebuilt sections, so non-data re-renders do zero grouping work. Playlist deletion routed through `removePlaylist(id:)` so the cache stays in sync

---

## 2026.5

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

### Unified queue context menu
- `UpNextContentView` and `QueueScreen` (full queue) now share a single `.contextMenu(forSelectionType: String.self)` path; the single-selection branch (`trackIDs.count == 1`) builds the full action set — `AddToPlaylistMenu`, View Album, View Artist, and Play Next — while multi-selection keeps `AddTracksToPlaylistMenu` + bulk Remove
- Removed the `#if targetEnvironment(macCatalyst)` per-row `.contextMenu { menu(content:) }` from `fullQueueView` and deleted the now-unused `menu(content:)` builder — Catalyst right-click now flows through the same selection-based menu instead of a parallel per-row one
- Both views were previously inconsistent: Up Next only offered Add to Playlist + Remove, while the full queue had a richer Mac-only per-row menu. Single code path means feature parity across Up Next / Full Queue and iOS / Mac

### Music service menu icon hit target (iOS 26)
- The music service selector `Menu` labels in `MediaSelector.swift` and `SearchScreen.swift` had an offset/undersized tap area on iOS 26
- Wrapped each label in an `.iconOnly` `Label` to restore the standard toolbar hit target
- `.iconOnly` re-tints the icon with the control color, so re-applied `.foregroundStyle(brandColor.gradient)` on the `Label` to restore the per-service brand color
- Kept `.frame(width: 24, height: 24)` on the icon image so sizing stays correct

### Search & library results grid layout
- New `PlayableContentGridView` — a two-column `LazyVGrid` that renders the extracted `PlayableContentRowView` per item (`.geometryGroup()` per cell)
- Used by search results and `AppleLibraryBrowseScreen` in place of the prior single-column list
- `SpotifySearchScreenUpdated` consolidated back to `SpotifySearchScreen` (preview + `SearchEmptyStateView` references updated)
- `RecentSearchesView` titles now leading-aligned and full-width (`maxWidth: .infinity`) instead of a fixed 70pt frame; tighter `VStack` spacing

### Average color extraction performance
- `UIImage.findAverageColor` now uses integer multiply (`r * r`) instead of `pow()` in the `.squareRoot` path — exact and far cheaper per pixel
- Pixel loop iterates rows contiguously (`y` outer, `x` inner) for better CPU cache locality
- Cache reads/writes go through `NSLock.withLock`, collapsing the lock/unlock boilerplate

### SoundCloud library screen parity with Spotify
- `SoundCloudBrowseScreen` rewritten from a `ScrollView` of horizontal carousels to a `List` of reorderable sections, matching `SpotifyLibraryScreen` and `AppleLibraryBrowseScreen`
- Liked Songs and Playlists now render as two-column `LazyVGrid`s of `PlayableContentRowView` (7 tracks + Play All, 8 playlists) with `NavigationLink` headers into the full lists
- Added `SoundCloudLibrarySection` enum, a `soundcloudLibrary` `SectionConfigurationStore`, and `ReorderSoundCloudLibrarySectionsView` so sections can be reordered/hidden via the toolbar filter button
- New `.reorderSoundCloudLibrarySections` sheet destination wired through `SheetDestination` and `AppRegistry`
- Auth-error and empty states preserved as List fallbacks; loading stays cursor-based (`updateLikedTracks`/`loadMoreTracks`) since SoundCloud has no offset/limit API

---
