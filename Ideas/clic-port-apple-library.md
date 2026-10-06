# Port to Clic: Apple Music library fixes

Fixes made in Cue on `claude/now-playing-layout` (2026-09-30) that Clic
(`~/Developer/Clic-deezer`) still needs. Clic shares the same code in
`Packages/SonosKit` and `Search/ArtistDetailView.swift`, so each one should
carry over close to as is. Cherry-pick the commit or copy the change.

## 1. Recently Played and Recently Added show the newest first — `5e5c1eef`

`AppleMusicBrowseService.updateUsersRecentPlayed` and
`updateUsersRecentAddedTracks` merged each refresh into the old list with
`updateOrAppend`, so an album already there kept its place and anything new
went to the end. Something just played never moved to the front. On the
first page (`offset == 0`), put the fresh rows in front:
`var fresh = OrderedSet(new); fresh.append(contentsOf: old)`.

Clic: same code at `AppleMusicBrowseService.swift:83`.

## 2. Library album covers and songs — `ba7bdfa4`

- **Covers.** MusicKit's library artwork is a `musicKit://artwork/library/…`
  URL. Only some carry an `https` URL inside them; most carry only the
  image's path on Apple's artwork server, in the `aat` query item, with the
  size as the last path component. `unwrappingMusicKitArtwork` in
  `Models/Mapping.swift` now builds
  `https://is1-ssl.mzstatic.com/image/thumb/<aat>/<size>bb.jpg` when there's
  no embedded `https` URL.
- **Songs.** MusicKit's library ids are the device's own (a long number,
  e.g. `2908773283971811772`). The web API's `/me/library/albums/{id}/tracks`
  doesn't know them, so an album opened from a MusicKit-sourced list showed
  "No Tracks". `albumLookup(id:)` now falls back to
  `MusicLibraryRequest<Album>` filtered by id, then `.with([.tracks])`,
  mapping `.song` entries with `toPlayableLibraryTrack`.

Clic: `albumLookup` at `AppleMusicBrowseService.swift:129` is web-API only.
Check whether Clic's library album list comes from MusicKit (where the ids
don't match) or from the web API (where they do) before porting the songs
fallback; the cover fix is safe either way.

## 3. A library artist opens the Apple Music artist — `2a66227f`

`ArtistDetailView.loadAppleLibraryArtist` showed only the library's albums,
and often didn't load at all. It now resolves the catalog artist first
(`/me/library/artists/{id}/catalog`, then an exact-name
`MusicCatalogSearchRequest`) and loads it through
`loadAppleArtist(id:) -> Bool`, a version of `loadAppleArtist()` that takes an
id. The old library page stays as the fallback.

Clic: `case (.libraryArtist, .apple)` at `ArtistDetailView.swift:562`.

## 4. Artist from a library album or library song — `57d0859b`

`ArtistDetailView.loadArtistData` had no case for `(.libraryAlbum, .apple)`,
so the artist line on a library album opened an empty page. Add the case
and look up `metadata?.artist` by exact name in the catalog
(`loadAppleArtist(named:)`). Do the same as a fallback for
`(.libraryTrack, .apple)` when its web API path leaves `artistContent` nil.

Known gap in both apps: "Various Artists", or an artist missing from the
catalog, still opens an empty page.
