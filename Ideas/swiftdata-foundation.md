# SwiftData Foundation

Introduce SwiftData as the local persistence layer. Currently the app has no local database — all content is in-memory (`OrderedSet` in `@Observable` services) or iCloud KV store. This is a prerequisite for Listening Stats, User Playlists, and the Plex/library cache.

## Two Separate Stores

Split into two `ModelConfiguration` objects in one `ModelContainer`, each with a different lifecycle and sync policy.

### Store 1: Content Cache (`contentCache.sqlite`)
- Local only — no CloudKit sync
- Ephemeral — can be nuked and rebuilt from Plex/Sonos at any time
- Bulk insert (20K+ songs), fast indexed queries by type/artist/title
- ~20–40 MB for a 20K song library (does not affect bundle size)

### Store 2: User Data (`userData.sqlite`)
- CloudKit private database sync — syncs across all the user's Apple devices automatically
- Permanent — never auto-deleted
- Small, surgical writes (stats log). Playlists and pins no longer need this store: they sync through `CKSyncEngine` (see [Cue Playlists and Pins](cue-playlists-and-pins.md))

## Content Cache Model

```swift
@Model class CachedContent {
    @Attribute(.unique) var id: String   // "service:type:nativeID"
    var cacheType: CacheType
    var title: String
    var subtitle: String
    var artworkURL: URL?
    var service: String                  // MusicService raw value
    var contentType: String              // ContentType raw value
    var sectionID: String?               // Plex section ID, playlist container, etc.
    var cachedAt: Date
    var playableData: Data               // JSON-encoded PlayableContent for full round-trip
}

enum CacheType: String, Codable {
    case plexTrack, plexAlbum, plexArtist, plexPlaylist
    case libraryTrack, libraryAlbum, libraryArtist, libraryPlaylist
}
```

`playableData` stores the full JSON-encoded `PlayableContent` so Sonos playback has everything it needs without re-fetching. A `toPlayableContent() -> PlayableContent` helper decodes it on demand.

Single model with a type discriminator keeps queries simple and cross-type lookups (e.g. "search everything in cache") trivial.

## Files

| Action | File |
|--------|------|
| Create | `Cue/Data/CueModelContainer.swift` — configure both stores + CloudKit |
| Create | `Cue/Data/CachedContent.swift` |
| Modify | `Cue/CueApp.swift` — initialize `ModelContainer`, inject into environment |
| Modify | `Packages/SonosKit/.../PlexBrowseService.swift` — write to cache after fetch |
| Modify | `Packages/SonosKit/.../LibraryBrowseService.swift` — write to cache after fetch |
