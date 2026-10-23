# Port to Clic: the performance pass

On 2026-10-02 Cue got a performance pass on `claude/apple-queue-perf` (nehayward/Cue#3). Clic shares much of the same code. This note lists which commits help Clic and which don't.

**Status: ported.** Everything in sections 1 and 2 (except the optional `1a9dba81`) is on Clic's branch `claude/cue-perf-port`, pushed and unmerged. It builds for the simulator and runs against the real speakers there. It hasn't been tried on a phone yet.

Four later Cue commits went over as well, since they're in the shared packages:
- `c52e61d2`: each album's "12 songs" label is worked out once.
- `4ab6b7b3`: Subsonic links are signed from a sign-in read once.
- `3275f499`: a speaker with no sleep timer is asked again every 15 s, not every poll. In idle Clic the time spent asking fell from 93 profile samples in 30 s to 6.
- `c80026c6` + `d95c0780`: speaker responses are unescaped in one pass.

**Checked against:** Clic `main` at `531c6b7d` (the checkout in iCloud `Active/Clic`). About half of the pass is about Cue playing on the device itself, which Clic doesn't do, so that part is skipped.

**How to bring a commit over:** rename the app folder in the patch, then apply it.

```bash
cd ~/Developer/Cue
git format-patch -1 --stdout <commit> | sed -e 's#\([ab]\)/Cue/#\1/Clic/#g' > /tmp/port.patch
git -C "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Active/Clic" apply /tmp/port.patch
```

## 1. These apply cleanly

`git apply --check` passes for each of these in Clic as it stands.

| Commit | What it fixes | Gain in Cue |
|---|---|---|
| `ffbe6e94` | **Plex badge from PNGs.** Clic's `Music Icons/Plex.imageset` still holds `plex.pdf`. That file wraps a bitmap, and every row redrew it from scratch. | **Biggest scroll win.** Drawing Plex Songs during a fast scroll went from 311 ms to 54 ms. |
| `6ae1cc0f` | **Speaker-response logs off the main thread.** `SonosLogInformation.log` wrote a file on the main thread at every poll. Release builds also built each message, then threw it away. | Less work on every speaker poll. |
| `7042c552` | **Grids load one page at a time.** `PlayableGridScreen` asked for the same page from many tiles at once. | No duplicate page requests. |
| `855be626` | **Each Apple Music artist picture is looked up once.** A library artist row with no picture ran a catalog search every time it appeared. Answers are now kept by name for the session. | No repeat lookups when scrolling back over Artists or a search. |
| `1a9dba81` | **Plex search songs carry their stream URL** (as `previewURL`). | Optional. Cue needed it to play on the device. In Clic it would only give Plex search rows a preview. |

## 2. Same bug in Clic, but needs porting by hand

The code has drifted, so these patches don't apply as they are. The problem is still in Clic in every case.

### Play history (`a8f07f97`)
- **No size cap.** History grows forever and is stored in iCloud key-value storage, which stops syncing past 1 MB.
  - Cue's fix: `PlayHistoryService.limit = 200`.
- **Two writes per play.** Every caller does `history.remove(x)` and then `history.insert(x, at: 0)`, which re-encodes and saves the whole list twice.
  - Cue's fix: one `record(_:)` method.
  - Callers in Clic: `URLPlayMediaView`, `PlayerSelectionView`, `ArtistDetailView`, `QueueManager`.
- **The header rebuilds every time.** `PlayHistoryView.swift:36` has `.tag(UUID().uuidString)`, a new id each render. Cue uses a stable tag.

### Search (`2d88c9ee`, `9fc92729`)
- **Debounce:** 150 ms → 250 ms (`MusicSearchService.swift:235`).
- **Trimmed search key:** `searchTaskKey` (`SearchScreen.swift:117`) should use the trimmed query, so a space typed between words doesn't search again.
- **Drop the history animation:** remove `.animation(.snappy, value: playHistoryService.history)` from `SearchScreen.swift:302`.
- **Ranking blocks typing:** `SearchRanking.sort` runs on the main thread.
  - It runs once per provider inside a merged search, then again on the merged list (`MusicSearchService.swift:388`).
  - Cue's fix: rank once, in `Task.detached`. Providers skip their own ranking when called from a merged search, which Cue does with a `@TaskLocal` flag.
- **Preview bar redraws the row:** `previewProgress` is read in the row's body, in both `PlayableContentView` and `PlayableContentRowView`, so a playing preview redraws the whole row 30 times a second.
  - Cue's fix: move it into a small `PreviewProgressBar` view.

### Player screen (`d977640a`, and the backdrop part of `02f34da0` / `764012fb`)
- **Marquee never rests** (`Marquee.swift:97`).
  - The task sets `startTime` once, so after the first pause the timeline runs every frame forever.
  - Cue's fix: loop rest → scroll → rest, setting `startTime = nil` while resting, and add `minimumInterval: 1.0 / 60` to the `TimelineView`.
- **Like button asks the server on every song change.** It looks the song up straight away (`LikeButtonView.swift:71` and `:108`), even while skipping quickly.
  - Cue's fix: wait 400 ms first.
- **Favourite caches write even when nothing changed.** This affects `FavoriteRatingCache.set` and the `favorites[trackID] = …` write in `MusicService+Favorite.swift:42`.
  - Cue's fix: skip writes that change nothing.
- **Backdrop colour work on the main thread.** `ArtworkMeshBackground.load()` calls `sampleColors` and `renderGradient` there (lines 62–64).
  - Cue's fix: make both `nonisolated static` and run them in `Task.detached`.
  - Also: snap to the new colours instead of fading when two song changes come less than 1 s apart.

### Grid covers at the tile's size (`0e6de111`)
- **Grids fetch full-size covers.** Clic's `ContentArtworkView` (`:47`) asks for the full 1200 px cover even for a 150 pt grid tile.
- **Cue's fix:** ask Plex (`/photo/:/transcode` width and height) and Subsonic (`getCoverArt` size) for 300 or 600 px instead.
- **Caching:** the size has to go into `imageID` (`#600`), or a small copy gets reused in the player and looks soft.

### Library paging (`a67c1524`)
- **Repeated page requests.** `PlayableList.swift:23` asks for the next page from every row in the bottom half as it appears, so one scroll sends a burst of identical requests.
  - Cue's fix: ask once from the last 15 rows, one page at a time, and stop when a page adds nothing.
- **Apple Music Songs restarts at the end.** `AppleMusicBrowseService.updateUsersAppleSongs` (`:48`) reads the last page's missing `next` as offset 0, so reaching the end loads the whole library again.
  - Cue's fix: a `userSongsComplete` flag, plus one assignment per page instead of one per song.
- **Skip:** the `PlayableListView` part of this commit. Clic has no `animatesNextFill`.

## 3. Doesn't apply to Clic

- **Device playback.** Clic plays on Sonos only, so none of the `LocalPlaybackService` work applies:
  - `ac256ad5`, `22886a5f`, `741007d2`, `8f6b645d`: the Apple Music windowed queue, `AppleSongStore`, stream windows, re-arming. Clic also has no `AppleMusicAPI.songs(ids:)`.
- **Cue-only screens:** `2b0f60e5` and `2c47c692` (Cue's own Up Next), and the `PlayerView` / `LocalNowPlayingPresenter` parts of `02f34da0` and `764012fb`.
- **Downloads:** `b105a28f` (ALAC and AAC files saved as `.m4a`).
- **Files and offline search:** `f62aee90`. Clic has neither.
- **`2cf86580`:** Clic's `Mapping.swift` already has no per-track regex, and Clic has no `OnDeviceCollectionScreen`.

## 4. Ideas for Clic, not measured

- **Sonos Up Next:** the same split as `2c47c692` might help. A song change would redraw only the rows on screen. Profile first.
- **Next cover:** the Sonos player could prefetch the next song's cover from the queue, as Cue's player now does.
