# User Playlists

Cue-native playlists separate from Sonos device playlists — stored in SwiftData, synced across the user's devices via CloudKit, and shareable with other Cue users via an export/import link.

Requires [SwiftData Foundation](swiftdata-foundation.md).

## Models

Stored in the **User Data SwiftData store** (CloudKit-synced):

```swift
@Model class UserPlaylist {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var tracks: [UserPlaylistTrack]
}

@Model class UserPlaylistTrack {
    var position: Int
    var playableData: Data   // JSON-encoded PlayableContent
    var addedAt: Date
    var playlist: UserPlaylist?
}
```

`playableData` preserves the full `PlayableContent` so tracks play back on Sonos without re-fetching. Tracks from any service (Spotify, Apple Music, Plex, etc.) can coexist in one playlist.

## Playlist Sharing — v1: Import/Export

SwiftData + CloudKit private DB syncs only across the *same user's* devices. Sharing between different users requires either raw CloudKit CKShare (not yet supported by SwiftData as of iOS 18) or a backend server.

**v1 approach — no backend needed:**
```
cue://playlist/import?data=<base64-encoded-JSON>
```
- Host taps "Share Playlist" → generates URL encoding playlist title + array of `PlayableContent` items
- Share via standard share sheet (AirDrop, iMessage, etc.)
- Recipient opens link → Cue decodes → shows import confirmation → saves to their own `UserPlaylist` store

This is a one-time snapshot, not a live-synced playlist. Good enough for "hey check out this mix."

**v2 (future):** Collaborative/live-updating playlists would require a thin Cloudflare Worker + D1 backend. The `id: UUID` field is designed to be swappable with a server-assigned ID for this migration.

Add `cue://playlist/import?data=` handling to `CueApp.handle()`.

## Distinction from Sonos Playlists

Today, "playlists" in Cue are Sonos device playlists stored via UPnP SOAP (`SonosAPI+Playlists.swift`). Those remain unchanged. User Playlists are a parallel, app-layer concept — useful for curating content across services that Sonos can't natively mix.

## Files

| Action | File |
|--------|------|
| Create | `Cue/Data/UserPlaylist.swift` |
| Create | `Cue/Data/UserPlaylistTrack.swift` |
| Create | `Cue/Playlists/UserPlaylistsScreen.swift` |
| Create | `Cue/Playlists/UserPlaylistDetailScreen.swift` |
| Modify | `Cue/Routing/RouterDestination.swift` — add playlist destinations |
| Modify | `Cue/Routing/AppRegistry.swift` — register screens |
| Modify | `Cue/CueApp.swift` — add `cue://playlist/import` handler |
