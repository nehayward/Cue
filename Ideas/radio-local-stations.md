# Radio: Local Stations & More Sources

Follow-ups to the Radio tab (`Cue/Radio/`). The tab's rule: **a station
belongs there only if it plays on this device as well as on a speaker.**
Today that is TuneIn (local by IP, trending, directory) and Apple Music
stations — both play locally (`LocalPlaybackService`: TuneIn as a resolved
live stream in `AVQueuePlayer`, Apple as a MusicKit `Station`) and on Sonos.
Sonos Radio and Sonos favorites are speaker-only, so they stay on Browse and
Search. Everything below is about making "near me" accurate and adding
sources that meet the rule.

What the rule asks of a new source: a stream URL the device can open (MP3 or
AAC; HLS only on newer speakers), and a way for Sonos to play the same
stream — every service with a Sonos service id (TuneIn, Apple Music) plays
through that id; an open directory with raw stream URLs needs the live-stream
URI form Sonos accepts, which the app doesn't have yet (Subsonic's
`DirectStreamProvider` is for files, not live streams).

## To do, in order

### 1. Live-stream playback in SonosKit
- Play a public MP3/AAC stream by URL: `x-rincon-mp3radio://<host>/<path>`
  as `CurrentURI`, with `audioBroadcast` DIDL metadata (title, artwork) so
  the player shows the station instead of the URL.
- New `ContentType`/`MusicService` arm for a direct stream, or reuse
  `.radio` with a `.directStream` service. Decide alongside `PlayableContent
  .sonosURI`.
- HLS only works on newer speakers; skip stations whose codec is HLS, or
  mark them so the row can say so.
- Prerequisite for 3, and for playing raw stream URLs pasted into
  `URLPlayMediaView`.

### 2. Location for "Local Radio"
- TuneIn places the local page by IP today. On a VPN or some cellular
  networks that's the wrong city. `Browse.ashx?c=local&latlon=<lat>,<lon>`
  fixes it.
- Ask for **reduced-accuracy** location only (`NSLocationDefaultAccuracyReduced`
  in Info.plist, `CLLocationManager` with `.reducedAccuracy`): city-level is
  all a station directory needs, and the prompt is much softer.
- Request it from the Radio tab the first time Local Radio shows, not at
  launch. Fall back to IP placement if denied.
- Pass `TuneInBrowsePage.local` a coordinate; `TuneInBrowseService.load()`
  refetches when the coordinate changes materially (> ~10 km).

### 3. Radio Browser as a source (radio-browser.info)
- Free, open, no key, ~50k stations with direct stream URLs, codec and
  bitrate. Geo search: `GET /json/stations/search?geo_lat=…&geo_long=…&geo_distance=<m>`;
  also `countrycode`, `state`, `tag`, and `name` search.
- Resolve a mirror by DNS (`all.api.radio-browser.info` → pick a host) rather
  than hardcoding one; send a `User-Agent` naming the app, as they ask.
- Add `RadioBrowserAPI` to MusicSearchKit (see `Docs/AddingMusicService.md`),
  a "Near You" row in `RadioScreen` driven by the location from step 2, and
  a Radio Browser section in the tab's search (`RadioSearch`).
- Filter out HLS and dead stations (`lastcheckok == 1`); mark a station's
  "click" (`/json/url/<uuid>`) when played so the directory's popularity
  stays honest.
- Needs its own Services toggle (`CoreFeatures`) like the other providers,
  so `showsRadioTab` counts it.

### 4. Smaller follow-ups on the tab itself
- "Recently Played" stations row from `PlayHistoryService` (radio plays are
  already recorded).
- A Home screen row pointing at the Radio tab — on iPhone it can land in
  More.
- Release notes entry for the tab.

## Considered and parked

| Source | Why not now |
|---|---|
| iHeartRadio | Best US local coverage, but the public API is unofficial and the terms are restrictive. Do it as a Sonos-service integration (like Pandora) if at all. |
| Apple Music | No local radio; genre/artist stations only. Already at the ceiling. |
| RadioDNS / FM lookup | Maps a frequency to a stream — great for "the 97.5 I hear in the car". Strong in the UK/EU, thin in the US. Revisit after Radio Browser. |
| Shoutcast / Icecast directories | Internet-only stations, weak on local broadcast; Shoutcast needs a paid key. Radio Browser covers the same ground. |
| TuneIn podcasts | The directory lists shows and episodes (`item="topic"`); Sonos plays TuneIn as station streams, so episodes need a different play path. Parser already drops them. |
| Sonos Radio | Speaker-only: its stations have no stream the device can open, so they fail the tab's rule. Stays on Browse. |
| Sonos favorites | Also speaker-only (`service: .unknown`, played from URI metadata). Stays on Search. |

## Files

| Action | File |
|--------|------|
| Add | `Packages/MusicSearchKit/Sources/MusicSearchKit/RadioBrowserAPI.swift` |
| Modify | `Packages/SonosKit/Sources/SonosKit/Models/PlayableContent.swift` (live-stream URI) |
| Modify | `Packages/MusicSearchKit/Sources/MusicSearchKit/Models/TuneIn/TuneInBrowse.swift` (`.local` with coordinate) |
| Modify | `Packages/SonosKit/Sources/SonosKit/TuneInBrowseService.swift` |
| Modify | `Cue/Radio/RadioScreen.swift`, `Cue/Radio/RadioSearch.swift` |
| Modify | `Cue/Info.plist` (location usage strings, reduced accuracy default) |
