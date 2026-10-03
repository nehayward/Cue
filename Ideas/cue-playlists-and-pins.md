# Cue Playlists and Pins

Playlists that belong to Cue rather than to a service, and pins at the top
of the library, both on every device the person signs in to with their
Apple Account (iCloud).

A Cue playlist holds songs from Apple Music, Plex, Subsonic and Files side
by side. It plays on the device and on a Sonos group like anything else in
Cue, and it works with no speaker on the network. Pins put the albums,
playlists, artists and stations someone plays most above every library, so
they're one tap away whichever service is selected.

This replaces [User Playlists](user-playlists.md) and takes playlists and
pins out of [SwiftData Foundation](swiftdata-foundation.md): neither
needs SwiftData any more (see Why CloudKit, and not SwiftData).

## Status

- [x] **Core model**: `Packages/CueLibrary` (branch `claude/cue-playlists-pins`).
  Pure Foundation, with 42 tests that run under `swift test` on Linux,
  including a randomized test that three devices editing apart converge.
  Not yet linked into any target.
- [ ] Everything below the model, one branch per session (see Phases).

## What the person gets

- **Cue Playlists**: make one from the Add to Playlist sheet, the queue
  ("Save Queue as Playlist"), or any service playlist ("Copy to Cue
  Playlist"). Add songs from any service. Reorder, remove (with undo),
  rename, add notes and pick a cover. A song can be in a playlist twice.
- **Pins**: Pin and Unpin in the item menu for albums, playlists (a
  service's or Cue's own), artists and stations. Pins show at the top of
  Browse whichever library is selected, in the person's order. A new pin
  goes first.
- **On every device**: the iPhone, iPad and Mac through iCloud, CarPlay
  through the iPhone, and the watch through the iPhone (a later phase).
- **Plays everywhere**: on the device it uses the existing mixed-service
  queue (one run per service). On Sonos it sends one `AddURIToQueue` per
  song, as `SonosService.queue(contents:…)` does today. Files songs are
  device-only, so on a speaker they're skipped and a banner says so.

## The model (`Packages/CueLibrary`, done)

| Type | What it is |
|------|------------|
| `CueItem` | A token-free reference to something in a service: `source`, `kind`, the service's own `id`, `server` where the id alone doesn't identify it (Subsonic, Files), plus what to show offline (title, subtitle, album, duration, ISRC, artwork). `extras: [String: String]` holds service-specific fields. `Source` and `Kind` are open-ended string types, so songs from a service a newer build added survive an older build's merge. |
| `OrderKey` | Fractional index (rocicorp's scheme, base 62 with an integer head). Moving or inserting one song writes one key. Appending counts `a0, a1 … az, b00`, so keys stay short. |
| `SyncedList<Element>` | An ordered list where every element has an `OrderKey` and a `changedAt`, and removals are dated tombstones (kept for 180 days). The merge is a per-element last-writer-wins: it's commutative, idempotent and associative, and gives the same order everywhere. Two songs dropped in one place on two devices at once share a key. They tie-break by entry id, and the next edit there gives them keys of their own. |
| `Stamped<Value>` | A last-writer-wins value: a playlist's name, notes and cover. |
| `CuePlaylist` | `id`, name, notes, cover (automatic mosaic, one item's artwork, or a custom image) and `entries: SyncedList<Entry>`. Each entry has its own id, so duplicates are allowed. |
| `CuePins` | `SyncedList<CuePin>` keyed by `CueItem.key`. |
| `CueLibrary` | All playlists, playlist tombstones and the pins in one value: what's saved on the device and what goes to the watch. `CueLibraryCoding` packs it as JSON, LZFSE-compressed on Darwin, with a leading byte as in `WatchSyncMessage`. |

### Rules the model sets

- **No sign-ins in synced data.** Plex `previewURL` and artwork carry
  `X-Plex-Token`; Subsonic URLs carry `u`/`t`/`s`. A `CueItem` keeps
  artwork as a server path (`CueItem.serverPath(of:)`), and the app adds
  the current server and token back when it draws it. The stream is rebuilt
  from the current sign-in at play time (`playbackStreamURL` already does
  this for Subsonic). `CueItem.carriesSignIn(_:)` is the check every
  record goes through before it's sent.
- **Only people's edits go into synced records.** Lookups, metadata
  refreshes and cross-service matches the app makes on its own stay in a
  local cache. In a last-writer-wins merge they would count as edits and
  bring back songs another device removed (`replaceItem` says so).
- **Clocks.** Merges go by each device's clock, as `WatchPicks` already
  does. A device whose clock runs far ahead wins ties it shouldn't. That's
  acceptable for playlists, and a hybrid logical clock can replace `Date`
  inside the model later without touching callers.

## iCloud sync: CloudKit through `CKSyncEngine`

Private database, one custom zone (`CueLibrary`):

| Record type | Name | Fields |
|-------------|------|--------|
| `Playlist` | the playlist's UUID | `encryptedValues["payload"]`: the packed `CuePlaylist`. A payload over 800 KB goes in a `CKAsset` instead (about 6,000 songs). |
| `Pins` | `pins` | `encryptedValues["payload"]`: the packed `CuePins` |
| `PlaylistCover` (later) | `cover-<playlist id>` | `CKAsset`, a custom cover image |

How the sync engine is used:

- **Saving.** Every local edit writes the store, then adds
  `.saveRecord(id)` to the engine's pending changes. Deleting a playlist
  adds `.deleteRecord`. `nextRecordZoneChangeBatch` builds records from
  the store at send time, so ten quick edits send once.
- **Conflicts** (`serverRecordChanged` in `sentRecordZoneChanges`): decode
  the server's payload, `merged(with:)` the local copy, write the result
  into the *server* record (which keeps its change tag) and queue it again.
  Because the merge is pure and tested, conflict handling is about ten
  lines.
- **Fetched changes**: if this device has a save pending for that record,
  merge. Otherwise replace the local copy outright, so a device that was
  away longer than the tombstone lifetime can't bring back removed songs.
  A fetched deletion removes the playlist (`CueLibrary.deletePlaylist`).
- **A save that hits a deleted record** (`unknownItem`): one device edited
  a playlist that another had deleted. Re-create it without system fields,
  so the edit wins and nothing the person just did is lost. This matches
  the model's "a later change beats a deletion".
- **State**: `CKSyncEngine.State.Serialization` goes to
  `Application Support/CueLibrary/sync-state.json` on every
  `.stateUpdate`. The library itself is
  `Application Support/CueLibrary/library.json`, saved with a 300 ms
  coalesce and atomically, the way `DownloadManager` saves its manifest.
- **Accounts**: with no iCloud account, everything works on this device
  and Settings says so. When someone signs in, the local library is
  uploaded and merged. Switching accounts moves the old library aside
  (`library-<hash>.json`) instead of deleting it, and starts fresh.
- **Encryption**: payloads go in `encryptedValues`, so they're end-to-end
  encrypted under Advanced Data Protection. Names live inside the payload,
  so nothing readable sits in an unencrypted field.

Setup that only the developer account can do:

1. Create the container `iCloud.dance.cue` (Xcode ▸ Signing & Capabilities
   ▸ iCloud ▸ CloudKit creates it with automatic signing).
2. Add `com.apple.developer.icloud-services = [CloudKit]` and
   `com.apple.developer.icloud-container-identifiers = [iCloud.dance.cue]`
   to `Cue/Cue-iOS.entitlements` and `Cue/Cue.entitlements` (Mac, TV,
   Vision). They sit next to the key-value store entitlement already
   there. Cue Mini, the widgets and the watch don't need it.
3. Before the first TestFlight build that syncs, deploy the schema from
   development to production in the CloudKit Console. Record types are
   created in development by the first save, but production builds can't
   create them, and they fail with "record type not found" until the
   schema is deployed.

### Why CloudKit, and not SwiftData

- SwiftData's CloudKit mirroring has no ordered relationships, no unique
  constraints and no conflict hook: two devices that reorder a playlist
  apart get an arbitrary order or duplicated rows. `CKSyncEngine` hands
  over each conflict, and the model's merge settles it.
- The model stays pure Foundation, tested on Linux, and the same value goes
  to the watch through WatchConnectivity (the watch has no iCloud
  entitlement).
- `CKSyncEngine` needs iOS 17, macOS 14, tvOS 17 and watchOS 10. Cue and
  Cue (Mac) target 26, the Apple TV 18 and the watch 10, so every target
  has it.

### Why not the iCloud key-value store

Cue already uses it (`CloudKeys`). It's 1 MB in total, shared by every key,
and play history alone fills it (see Found on the way). It has no conflict
information either. Pins would fit, but one sync path for both is simpler.

## Playing a Cue playlist

- **`CueItem` ↔ `PlayableContent`** (SonosKit, beside `PlayableContent`):
  `CueItem(_ playable:)` strips tokens and device paths.
  `PlayableContent(_ item:)` rebuilds it:
  - Apple Music: the id is enough. A library id (`i.…`) prefers its
    catalog id from `extras`.
  - Plex: the id already carries the server's machine id, and the artwork
    path is rebuilt with the current server.
  - Subsonic: `SubsonicAPI.streamURL`.
  - Files: a `FilesIndex` lookup by id.
  - TuneIn: the station id.
- **Availability**, worked out per entry on the device and kept in memory:
  playable · sign in to <service> · on another Plex/Subsonic server · not
  on this device (Files) · this device only (Files, while a speaker is the
  destination). Unavailable rows are dimmed with the reason, and Play
  skips them.
- **Play** through `PlayDestinationRouter.play(contents, position:,
  shuffle:, from: origin, queue:)`. `origin` is the playlist as a
  `PlayableContent` with a new `MusicService.cue`, so the player's
  "Playing from" and the saved `localQueueSource` lead back to the
  playlist. Adding the case makes every exhaustive switch over
  `MusicService` fail to compile, about 20 files: that's the checklist, as
  in `device-first-services.md`.
- **Sonos**: the existing per-item queue path. Apple Music and Plex songs
  need those services linked in the Sonos app, as they already do.

## Where it shows

**iPhone, iPad and Mac** (all built from `Cue/`):

- **Browse**: every library screen (Apple, Plex, Subsonic, Files, Offline)
  opens with the same two things:
  - **Pinned**: a shelf of square tiles, two rows on iPad and Mac, with
    Edit Pins for reordering and unpinning.
  - **Cue Playlists**: a row that opens the list.

  On Apple both are `AppleLibrarySection` cases, so `SectionConfiguration`
  can reorder and hide them. The other screens put a shared
  `CueLibrarySections` view first in their `List`.
- **`CuePlaylistScreen`**: a screen of its own rather than another arm in
  `MediaDetailView`. Its edits are local and instant, not service calls,
  and it needs the availability states. It reuses `PlayableContentView`
  rows, the header style, Play/Shuffle, and the undo toast
  (`PlaylistEditCoordinator`'s stack).
- **Add to Playlist sheet**: a **Cue** segment, first and the default,
  which takes any song from any device-first service, and albums expanded
  into songs. New Playlist there makes a Cue playlist. `LastPlaylist`
  learns `.cue`, so Add to Last Playlist and the Mac's Playlist menu
  include Cue playlists.
- **Item menu** (`PlayableMenuView`): Pin and Unpin on albums, playlists,
  artists and stations. On a Cue playlist: Play, Shuffle, Play Next, Pin,
  Rename, Duplicate, Delete.
- **Queue**: "Save Queue as Playlist" makes a Cue playlist, on the device
  queue as well as on a group. Today `QueueMoreInfoView`'s Save Queue only
  makes a Sonos playlist, which stays as a second choice while Sonos is on.
- **Search**: Cue playlists whose names match come first.

**CarPlay**: the Library tab adds the pins as its header grid and a Cue
Playlists shelf first (`CarPlayLibrary.shelves`). It plays on the device as
everything in CarPlay does.

**Apple Watch** (later): a Cue playlist can be added to the watch. The
iPhone sends the picked playlists' entries through `WatchSyncMessage`. The
watch downloads the Plex and Subsonic songs and leaves out Apple Music and
Files, as it does today.

**Apple TV and Cue Mini**: nothing for now. tvOS has no library screens
yet. When the Apple TV gets a device player (`device-player-roadmap.md`) it
can read the same CloudKit zone.

## Phases

One branch per session; each says what "done" means.

- [x] **Core model**: `claude/cue-playlists-pins`.
  `Packages/CueLibrary`, tests, this doc.

- [ ] **Store and conversion**: `claude/cue-library-store`.
  - Link `CueLibrary` into Cue, Cue (Mac) and Cue (Vision), as WatchSync is
    linked.
  - SonosKit depends on it for `PlayableContent+CueItem.swift`, with tests
    in SonosKitTests: no token survives the round trip, and each service
    rebuilds a playable item.
  - `Cue/Library/Cue/CueLibraryStore.swift`: `@Observable`, `.shared`,
    `library.json`, saving coalesced.
  - `MusicService.cue`.
  - Done when: the conversion tests pass, and a playlist made in a debug
    screen survives relaunch.

- [ ] **Playlists UI**: `claude/cue-playlists-ui`.
  - `CuePlaylistsScreen`, `CuePlaylistScreen`.
  - `RouterDestination.cuePlaylists` and `.cuePlaylist(id:)`.
  - The Add to Playlist sheet's Cue segment, `NewPlaylistView`, `LastPlaylist`.
  - Save Queue as Playlist, Copy to Cue Playlist, and menu items in
    `PlayableMenuView`.
  - Done when: a playlist mixing Apple Music, Plex and Subsonic songs plays
    on the iPhone with no speaker, and on a Sonos group skipping only Files
    songs. Reorder and remove with undo work on the iPhone and the Mac.

- [ ] **iCloud sync**: `claude/cue-cloud-sync`.
  - Entitlements and container (the setup above).
  - `Cue/Library/Cue/CueCloudSync.swift`, the `CKSyncEngine` delegate.
  - Settings ▸ iCloud row: synced, syncing, or "iCloud is off".
  - Done when: a playlist made on the iPhone shows on the Mac within
    seconds. Edits made on both while one is offline merge. Deleting on one
    removes it on the other.

- [ ] **Pins**: `claude/cue-pins`.
  - Pin and Unpin in `PlayableMenuView`.
  - `PinnedShelf` and `EditPinsSheet` in `Cue/Library/Cue/`, added to each
    library screen, and `AppleLibrarySection.pinned` and `.cuePlaylists`.
  - Done when: a pin made on the Mac shows on the iPhone in the same place,
    and a pin from a service that isn't signed in on this device is dimmed,
    not hidden.

- [ ] **CarPlay and the Mac menu**: `claude/cue-playlists-carplay`.
  - Pinned header grid and the Cue Playlists shelf in
    `CarPlayInterface`/`CarPlayLibrary`.
  - The Mac's Playlist menu lists Cue playlists.

- [ ] **Apple Watch**: `claude/cue-playlists-watch`.
  - `WatchPick.Kind` gains a Cue playlist, whose entries travel in the
    application context.
  - The watch downloads the Plex and Subsonic songs in it.

- [ ] **Sharing**: `claude/cue-playlist-sharing`.
  - Share sends a `.cueplaylist` file (packed `CuePlaylist`) or a
    `cue.dance/p/<id>` link that the Worker in `Website/` serves.
  - Opening one shows Import. This is a snapshot, not a live shared
    playlist.

- [ ] **Cross-service matching**: `claude/cue-playlist-matching`.
  - When an entry's service isn't on this device (no Apple Music
    subscription here, a different Plex server), find the same recording
    on one that is: ISRC first, then title, artist and duration.
  - Matches are cached on the device only.
  - Also Export to an Apple Music, Plex or Subsonic playlist, for the
    songs that service has.

## Open questions

1. **Where Cue Playlists sit.** This doc puts Pinned and a Cue Playlists
   row at the top of every library. The alternative is a "Cue" library in
   the `MediaSelector` menu (Pinned, Playlists, Downloads, History), which
   gives Cue's own things one home but hides pins behind a menu.
2. **Super or free.** Playlists are table stakes for a player, so this doc
   assumes free, with a `GatedFeature.cuePlaylists` case set to `.free`.
   `FeatureGate` asks for a case for anything that might ever be held back.
   Alternatives: three playlists free and unlimited with Super, or sync as
   the Super part.
3. **Songs as pins.** Left out: a pinned song is what a playlist is for.
   Apple Music allows it.

## Found on the way

- **Play history has no cap and lives in the iCloud key-value store**
  (`PlayHistoryService`, `CloudKeys.playHistory`). Every play inserts a
  `PlayableContent` (`QueueManager.swift:115`,
  `PlayDestinationRouter.swift:224`) and nothing trims the list. Once the
  store reaches its 1 MB total, iCloud stops syncing *every* key, scenes and
  the `hasSubscription` flag that widgets read included. It also syncs Plex
  and Subsonic tokens, which ride in `previewURL`. A cap of about 200 and
  stripping tokens (`CueItem.serverPath`) would fix both; that's its own
  small branch.
- `CloudKeys.searchHistory` (`com.cue.searchHistory`) is never written.
