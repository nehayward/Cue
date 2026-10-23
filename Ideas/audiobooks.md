# Audiobooks

Books in Cue, from the servers people already keep them on: **Plex** (a
Music library kept for books, or albums tagged with an audiobook genre) and
**Audiobookshelf**. Both pass the device-first rule
(`device-first-services.md`): the phone plays the files straight from the
server, and so does a speaker.

**Status:** on `claude/audiobooks`, built in Xcode and on the phone
(2026-10-19). The pure-Foundation parts (timeline, chapters, Plex resume,
Audiobookshelf JSON, URLs, Audible's catalog) have unit tests. The package's
test target doesn't build as a whole for stale tests elsewhere
(`MockTokenRefreshHandler`, `PlexTests`' `externalURIs`).

## Where this came from

- **2026-10-02, "Audiobooks feature decision" (cloud session).** The
  recommendation: books inside Cue rather than a separate app, as their own
  mode (resume per book, speed, ±skips, kept out of the music queue and
  stats). Sources in order: Audiobookshelf, Plex, then `.m4b` in Files. No
  code was written.
- **2026-10-08, "Cue feature readiness and audiobooks".** Its branch
  `claude/cue-features-audiobooks-zx0yk1` holds a roadmap refresh and a
  one-line onboarding fix, not audiobook code.
- **Clic** has a full Audible feature (`Clic/Library/Audible/`,
  `MusicSearchService+Audible.swift`, `SkipIntervalButton`). It plays
  through the speaker's Audible service over SMAPI, so it can't come to Cue
  under the device-first rule. Cue reuses its shape: the same
  `ContentType.audiobook` case, the progress bar, the ±skip buttons.

## How it fits

| Piece | Where |
|---|---|
| A book in lists | `ContentType.audiobook` (Plex album / Audiobookshelf item); opens `RouterDestination.audiobookDetail` |
| A book's files | ordinary `.track`s (Plex tracks; Audiobookshelf parts with id `item\|index\|file`) |
| Book time ↔ file + offset, chapters | `AudiobookTimeline`, `AudiobookChapter` (MusicSearchKit/Audiobooks) |
| Where the listener is | `AudiobookProgress`; this device's in `AudiobookProgressStore` (App Support), the server's read on open; newer wins |
| Loading a book | `AudiobookLibrary` (Plex: `PlexAPI+Audiobooks`; Audiobookshelf: `AudiobookshelfAPI`) |
| Playing it | `AudiobookPlayer`: replaces the queue with the files from the resume point, on this device or the route's speaker; follows `PlaybackRoute.presented` every 2 s to save the place and sync the server |
| Speed | `AudiobookPlayer.rate`, each book's own (a book never changed plays at 1×), applied by `LocalPlaybackService.applyPlaybackRate` to a book's files only; the clock runs at that rate. Speakers stay at 1× |
| Transport | Player: −15 s / +30 s replace Previous / Next. Lock Screen: skip commands and a rate command (`LocalNowPlayingPresenter`) |
| Player menu | Previous / Next Chapter, the chapters (device and speaker) and Speed (device) — `AudiobookPlayerMenuItems` |
| Chapter line | The player's origin line reads the chapter playing and opens the chapters (`AudiobookChapterLine`) |
| Sleep timer | End of Chapter in place of End of Song: the player's own timer, kept on the chapter's end at the speed playing (`AudiobookPlayer.sleepAtEndOfChapter`) |
| Audiobooks tab | `AudiobooksScreen`: the book listened to last with Resume (`AudiobookResumeCard`), Continue Listening, Audiobookshelf's Recently Added, Recently Played, then All Books per server. Shown while Audiobookshelf is signed in or Plex had books when last asked (`AppStorageKeys.hasPlexAudiobooks`); Settings ▸ Appearance can hide it |

### Plex

- Plex has no book library type. The usual setup is a Music library kept
  for books, often matched by the Audnexus agent (book = album, author =
  album artist, a file per chapter or one `.m4b`).
- Settings ▸ Services ▸ Plex ▸ Audiobooks lists the server's other Music
  libraries with a switch each (`PlexAudiobookSettingsSection`). Until one
  is switched, those named for books or matched by Audnexus are on
  (`PlexAudiobookRules`). "Books in the Music Library" also takes albums in
  the music library with an audiobook genre.
- The Plex library screen shows an Audiobooks row when there's anything to
  show.
- Pulling to refresh a list of Plex books has Plex scan the libraries kept
  for books (`/library/sections/<key>/refresh`, owner only) and waits for
  it, up to 30 s, with "Scanning…" in the title bar (`PlexBookScan`). The
  music library isn't scanned for genre-tagged books: it can be large.
- Resume comes from each file's `viewOffset` / `viewCount` /
  `lastViewedAt` (`PlexAudiobook.progress`). **Plex keeps `viewOffset` only
  with "Store track progress" on in the library's advanced settings**; the
  settings footer says so. This device keeps its own place regardless.
- Chapters come from the `.m4b`'s marks: each file of a book of up to 8 is
  asked on its own with `includeChapters=1`, read for its `Chapter` list
  alone (`PlexChapterLookup`; a batch request for several files came back
  without them). Plex lists an `.m4b`'s marks only when it read them at
  scan, so a file it has none for is read with AVFoundation
  (`AudiobookChapterReader`, cached in Caches/AudiobookChapters.json). A
  file with no marks anywhere is one chapter named for it; a book whose
  only chapter is the whole book shows no chapter list.
- A book with no marks anywhere takes Audible's chapters when the Audnexus
  agent matched it (the ASIN in the album's guid,
  `com.plexapp.agents.audnexus://<asin>`), from `api.audnex.us` —
  `AudnexusChapters`, laid on the book only when its length is Audible's,
  with or without Audible's branding at each end.
- A book no agent matched (`com.plexapp.agents.none`) is looked for in
  Audible's catalog by its title and author (`AudibleCatalog`, the search
  Audiobookshelf's own Audible match makes), and the editions within a
  minute and the tolerance of its length are fitted the same way, closest
  first. Single-file mp3 rips of Audible books are the usual case: they
  carry no `CHAP` frames, but their length is Audible's to the second.
- AVFoundation reads an mp3's ID3 `CHAP` frames as chapters (checked on
  macOS 27 with an ffmpeg-made file), so mp3s need no reader of their own.
- A file Plex lists but answers 404 for (moved since the scan, or a library
  folder out of its reach) gets a notice on the book's page and isn't read
  for chapters (`Audiobook.filesMissing`, a one-byte range request when the
  book opens). Audiobookshelf's `isMissing` sets the same.
- `AudiobookAudit` (Debug, `-AudiobookAudit <title>`) saves what Plex says
  about a book and each file, walks each file's ID3 frames or MP4 boxes over
  range requests, and loads it as its page does, for both servers; the
  report is in Documents/AudiobookAudit.
- On a speaker, Plex files play through Plex's Sonos service (sid 212), as
  for music. While a speaker plays, `AudiobookPlayer` sends the timeline
  reports the device sends itself through `PlayReporter`.

### Audiobookshelf

- Signed in to in Cue (`AudiobookshelfManagementView`): `POST /login` with
  `x-return-tokens`, access + refresh tokens in the keychain, renewed on a
  401. Servers before 2.26 give one token that never expires; it's used
  the same way.
- Each play opens a listening session (`POST /api/items/<id>/play`,
  `forceDirectPlay`). Its track URLs (`/public/session/<id>/track/<index>`)
  need no sign-in, which is what lets a speaker fetch them. With no session
  open, a file URL with the access token in the query stands in (good for
  the token's hour).
- Synced every 15 s and on pause (`/api/session/<id>/sync`, with what was
  heard since, for the server's listening stats); closed when another book
  or music takes over. A session the server has dropped (404) falls back
  to `PATCH /api/me/progress`. Sessions unsynced for 30 h aren't trusted;
  a relaunch with a book loaded opens a fresh one, and so does a book file
  that fails to load (once a minute at most).
- Library screen: library picker, Continue Listening, All Books (sorts:
  title, author, recently added, length), Recently Added. Search covers
  every book library.
- Chapters: the server's (ffprobe's, at scan), else the files' own read
  with AVFoundation through the signed file URL (never a session's, which
  may have ended), else Audible's for a book matched there: the server's
  own Lookup (`/api/search/chapters?asin=`), fitted as for Plex; else
  Audible's for the edition found by title and author, as for Plex.
- Descriptions are HTML; `AudiobookText.plain` reads them as text (Plex's
  book agents fill summaries with `<br />` too).

## Left to do

One item per branch, as in the roadmap.

- [x] **Build and fix** — builds in Xcode; deployed to the phone.
- [x] **The test server's Plex Audiobook library** (not Cue's) — every
  file in it answered 404: the library's folder had been renamed on the
  NAS (`Audiobook` to `Audiobooks`). Pointed at the new name and scanned
  (2026-10-19); all four books stream, and the Tolkien books take
  Audible's chapters on Plex too.
- [ ] **An mp3's own chapters on Plex** — not possible from Cue: Plex
  strips the ID3 tag from a part as it sends it, `download=1` too (The
  Two Towers comes 57 KB short either way, starting at the first audio
  frame), so an mp3's `CHAP` frames never arrive. Audible's chapters
  stand in; the same file on Audiobookshelf keeps its own.
- [ ] **Check on a speaker** (unverified):
  - a 10 h+ `.m4b` from Plex through sid 212, seeking late in the file;
  - Audiobookshelf session URLs with the `ext=.m4a` hint (Sonos has no
    `.m4b` in its list);
  - the device → speaker → device hand-off of a book.
- [ ] **Plex search finds books as books** — a Plex search result from a
  book library is still an `.album`. Map albums whose `librarySectionID`
  is a book library to `.audiobook` (`PlexAlbum.toPlayable`).
- [ ] **Keep genre-tagged books out of the music lists** — they show under
  both Albums and Audiobooks today.
- [x] **Download a book** — whole, from the book page, on Plex and
  Audiobookshelf; plays offline from a copy of the book kept beside its
  files (`AudiobookDownloads`). Checked in the Simulator: both copies of
  The Two Towers (598 MB each) in under 10 s, played with Offline Mode on.
- [ ] **Report offline listening** — Audiobookshelf's `/api/session/local`
  for what was heard offline. Opening a book sends this device's place
  when it's newer than the server's (`AudiobookLibrary.sendNewerPlace`),
  so a place or a finish from offline gets there, but the server's stats
  miss the time. CarPlay's Audiobooks tab offline (it lists the servers'
  shelves).
- [x] **CarPlay** — an Audiobooks tab (Recents folded into a Home tab to
  make room: an audio app gets four): Continue Listening as rows with a
  progress bar, then each server's books; a book plays from where it was
  left; Now Playing's skips are the Lock Screen's, and a
  `CPNowPlayingPlaybackRateButton` steps 1× to 2× in place of shuffle and
  repeat, and the chapter's place in a circle opens the chapter playing
  (with a bar and its time left) and the ones to come. Checked with `-AudiobookAuditCarPlay` in the Simulator, not yet
  in a car or the CarPlay simulator.
- [x] **Apple Watch** — books are watch picks like albums: added from the
  watch's Audiobooks shelves or Add to Apple Watch on the iPhone, their
  files downloaded as the server keeps them, played from their place with
  ±15/30 s skips, chapters and each book's speed. Places cross with the
  picks both ways (newer wins), and Audiobookshelf's token is lent, the
  iPhone keeping the refresh token. Not yet built or tried on a watch.
  Left: a sleep timer, and the watch telling the server itself (the iPhone
  does when it next opens the book).
- [x] **Sleep timer: end of chapter** — End of Chapter, on this device and
  a speaker.
- [x] **Chapter navigation** — Previous / Next Chapter and the chapter line
  in the player.
- [x] **Audiobooks tab** — the last book one tap from Resume.
- [ ] **Chapter scrubber** — the scrubber across the chapter playing rather
  than the file, for a 20 h `.m4b`.
- [ ] **Lock Screen chapters** — Previous / Next Chapter in place of the
  skips, as a setting.
- [x] **Speed per book** — each book keeps its own speed; one never
  changed plays at 1×.
- [ ] **Audiobookshelf single sign-on** — OpenID-only servers are refused
  with a message. The mobile PKCE flow is in the research notes below.
- [ ] **`.m4b` in Files** — the Files provider already takes the extension;
  a folder of books could use the same `AudiobookPlayer`.

## Research notes (2026-10-19)

Checked against Audiobookshelf v2.37.1's source (its API docs say they're
out of date) and Plex community setups (Chronicle, python-plexapi,
Audnexus.bundle, seanap's guide).

- Audiobookshelf access tokens last 1 h on v2.31+ (12 h on 2.26–2.30),
  refresh tokens 30 days, rotated on every refresh with a grace period.
  `?token=` works on any `/api/*` route; covers need no sign-in. A
  maintainer advises against API keys for third-party apps.
- `/public/session/<id>/track/<index>` (v2.22+) lives while the session
  does: it ends on close, on a new `/play` from the same device id, on a
  server restart, or after 36 h without a sync that adds listening time.
- `PATCH /api/me/progress` records no listening time; only session syncs
  count in the server's stats.
- Plex's played threshold for audiobooks is reported as 99 % (PMS 1.21.2
  notes) or 90 % (Chronicle) — untested.
- Plex's custom metadata providers (PMS 1.43, December 2025) don't cover
  Music libraries yet, and legacy agents are due to go in 2026, so some
  Audnexus libraries may fall back to local tags. That's why the agent is
  only one hint among others.
