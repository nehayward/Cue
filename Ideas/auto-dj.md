# Auto-DJ

When the active group's queue runs low (fewer than 3 tracks remaining) and the group is playing, automatically seed more tracks based on the most recently played content. SUPER subscription feature with a user toggle.

## Service

`AutoDJService` — `@Observable final class`, `static let shared`.

**Poll loop:** every 30 seconds, checks `SonosAPI.getQueueCount(IP:)` for the active group.

Only fires when all conditions are met:
- `subscriptionService.subscription.isActive`
- `autoDJEnabled` (`@AppStorage` user toggle)
- Group is actively playing (`coordinatorRoom.isPlaying`)
- Playback service is `.queue` (not radio, not an inline Sonos playlist)

**Seed logic by service:**

| Last played service | Action |
|---|---|
| Apple Music / library | Build a `songRadio` content item from the track's ID → `SonosAPI.startRadio()` (hands off to Apple Music's radio algorithm) |
| Spotify | `SpotifyAPI.artistTopTracks(id: metadata.artistID)` → append via `SonosService.queue(contents:group:position:.end)` |
| Other (Tidal, TuneIn, Plex, SoundCloud) | No-op — graceful skip |

**Debounce:** skip if seeded within 60 seconds (`lastSeededAt: Date?`).

**User feedback:** `AlertService.shared.showAlert(with: "Auto-DJ added more tracks", imageName: "wand.and.stars")`

## Known Limitation

30-second poll is the best available. Sonos's local SOAP API has no queue-empty push event, so polling is the only mechanism. For albums and long playlists this never fires, which is correct.

## Settings Toggle

New row in `PreferenceScreen`: "Auto-DJ" toggle backed by `@AppStorage(AppStorageKeys.autoDJEnabled)`. Gated with `.paywall(!subscriptionService.subscription.isActive)` + "SUPER" badge when locked.

## Files

| Action | File |
|--------|------|
| Create | `Clic/AutoDJ/AutoDJService.swift` |
| Modify | `Packages/Defaults/.../AppStorageKeys.swift` — add `autoDJEnabled` key |
| Modify | `Clic/Preferences/PreferenceScreen.swift` — add toggle row |
| Modify | `Clic/ClicApp.swift` — `_ = AutoDJService.shared` on appear |
