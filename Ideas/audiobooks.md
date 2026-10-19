# Audiobooks

Books in Cue, from the servers people already keep them on: **Plex** (a
Music library kept for books, or albums tagged with an audiobook genre) and
**Audiobookshelf**. Both pass the device-first rule
(`device-first-services.md`): the phone plays the files straight from the
server, and so does a speaker.

**Status:** first slice on `claude/audiobooks`. Not yet built in Xcode. The
pure-Foundation parts (timeline, chapters, Plex resume, Audiobookshelf
JSON, URLs) have unit tests that pass on Linux.

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
| Speed | `AudiobookPlayer.rate`, applied by `LocalPlaybackService.applyPlaybackRate` to a book's files only; the clock runs at that rate. Speakers stay at 1× |
| Transport | Player: −15 s / +30 s replace Previous / Next. Lock Screen: skip commands and a rate command (`LocalNowPlayingPresenter`) |
| Player menu | Chapters (device and speaker) and Speed (device) — `AudiobookPlayerMenuItems` |

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
- Resume comes from each file's `viewOffset` / `viewCount` /
  `lastViewedAt` (`PlexAudiobook.progress`). **Plex keeps `viewOffset` only
  with "Store track progress" on in the library's advanced settings**; the
  settings footer says so. This device keeps its own place regardless.
- Chapters come from the `.m4b`'s marks (`includeChapters=1`, read for books
  of up to 8 files), else one chapter per file.
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

## Left to do

One item per branch, as in the roadmap.

- [ ] **Build and fix** — first Xcode build of this branch, then a pass on
  the phone with a Plex audiobook library and an Audiobookshelf server.
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
- [ ] **Download a book** — whole-book downloads for offline listening
  (`DownloadManager` takes Plex files one at a time today; nothing for
  Audiobookshelf), and `/api/session/local` to report offline listening.
- [ ] **CarPlay** — a Books section with Continue Listening; the car's Now
  Playing with skip and a `CPNowPlayingPlaybackRateButton`.
- [ ] **Sleep timer: end of chapter** — chapters are book time, so the timer
  can stop at the next chapter's start.
- [ ] **Speed per book** — `rate` is one setting for every book today.
- [ ] **The player's title** — shows the file's title; the book and chapter
  would read better (the Lock Screen already does this).
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
