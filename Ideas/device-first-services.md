# Device-First Services

Cue is a music player first and a Sonos client second. The consequence for
services is the rule the Radio tab already lives by
(`radio-local-stations.md`): **a service belongs in Cue only if it plays on
this device as well as on a speaker.** This note is the audit of where each
service stands against that rule, and the plan for removing the ones that
fail it.

## Audit

What decides device playback is `LocalPlaybackService.backendKind(for:)`
(`Cue/Services/LocalPlaybackService.swift`). Its two backends are MusicKit's
`ApplicationMusicPlayer` (Apple Music, DRM'd audio) and `AVQueuePlayer` for
anything with a stream URL or file. The Sonos side is `PlayableContent.uri`
(`Packages/SonosKit/.../Models/PlayableContent.swift`).

| Service | Device | Sonos | Verdict |
|---|---|---|---|
| Apple Music | Full track via MusicKit (needs subscription) | `x-sonos-http:…?sid=204` | **Keep** |
| Plex | Full track off the user's server | `x-sonosapi-hls-static:…?sid=212` | **Keep** |
| Subsonic (Navidrome, Airsonic, Gonic) | Full track via `/rest/stream` (`DirectStreamProvider`) | Speaker fetches the same HTTP URL | **Keep** |
| TuneIn | Live stream resolved from the station id | `x-sonosapi-stream:…?sid=333` | **Keep** |
| Files (user folder) | The file itself | None (`playsOnDeviceOnly`) | **Keep, decide** (device-only, see Open questions) |
| Spotify | 30-second preview clip only | `x-sonos-spotify:…?sid=12` | **Remove** |
| Tidal | None | `…?sid=174` | **Remove** |
| Deezer | 30-second preview clip only | `x-sonos-http:tr-flac…?sid=2` | **Remove** |
| SoundCloud | None | `x-sonos-http:track-…?sid=160` | **Remove** |
| Pandora | None (pure SMAPI) | `x-sonosapi-radio:…?sid=236` | **Remove** |
| Sonos Radio | None (speaker-only) | `x-sonosapi-radio:…?sid=303` | **Remove** |
| Music Library (the speaker's NAS/share index) | None | `x-rincon-playlist:RINCON_…` | **Remove, decide** (see Open questions) |
| Last.fm | Metadata only (artist top tracks) | n/a | Keep, not a service |

Spotify can never cross the line: Spotify's API hands out no stream URL and
its iOS SDK only remote-controls the Spotify app. `PlayAction/QueueListView
.swift` already hard-codes the consequence ("A Spotify or Tidal link has no
local backend" → fall back off Device). The `SpotfiySonos/` folder is
Spotify browsed through Sonos' SMAPI proxy with the household's credentials;
it yields metadata only.

## Footprint of the services to remove

Files that reference each service (Swift, excluding tests), September 2026:

| Service | App targets | Packages |
|---|---|---|
| Spotify | 52 | 66 |
| Deezer | 23 | 23 |
| SoundCloud | 18 | 17 |
| Tidal | 13 | 32 |
| Pandora | 11 | 11 |
| Sonos Radio | 7 | 17 |

Whole files that go (app): `Cue/Library/Spotify/` (4 files),
`Cue/Library/SpotifyBrowseScreen.swift`, `Cue/Search/SpotifySearchView.swift`,
`Cue/Search/TidalSearchView.swift`, `Cue/Library/DeezerBrowseScreen.swift`,
`Cue/Library/SoundCloudBrowseScreen.swift`,
`Cue/Library/PandoraBrowseScreen.swift`,
`Cue/Library/SonosRadioBrowseScreen.swift`.

Whole files that go (packages): in MusicSearchKit `SpotifyAPI.swift`,
`SpotifyAuthenticatorService.swift`, `SpotifyOpenGraph.swift`,
`SpotfiySonos/` (4), `Models/Spotify/` (16), `TidalAPI.swift`,
`Models/Tidal/` (14), `DeezerAPI.swift`, `DeezerLinkResolver.swift`,
`Models/Deezer/` (6), `SoundCloudAPI.swift`, `Models/SoundCloud/` (3),
`PandoraAPI.swift`, `SonosRadioAPI.swift`, `SonosRadioHome.swift`, and the
five icon imagesets; in SonosKit `SpotifyAuth/`, `SpotifyBrowseService`,
`DeezerBrowseService`, `SoundCloudBrowseService`, `PandoraBrowseService`,
`SonosRadioBrowseService`, `SonosAPI+SonosRadio`, `URL+SonosRadioArtwork`;
in SonosKitMini the Spotify and Tidal imagesets.

Shared code that changes rather than goes:

- `MusicService` (SonosKit) and `MediaSearchService` (MusicSearchKit): drop
  the six cases. Every `switch` over them across the app then fails to
  compile, which is the checklist.
- `PlayableContent.uri` / `sonosURI`: drop the six URI arms and the
  `SA_RINCON…` service-account strings for those services.
- `Mapping.swift` (SonosKit): drop the Spotify, Tidal, Deezer, SoundCloud
  mappers.
- `CoreFeatures.preferredDefaultService` and `syncEnabledServices`: the
  order becomes Apple → Plex → Subsonic → TuneIn → Files.
- `SearchScreen`, `FilterView`, `SearchSelection`, `MediaSelector`,
  `BrowseScreen`, `SectionConfiguration`: remove the tabs and filters.
- `Cue/Playlist/` (5 files): playlist editing stays for Apple and Plex,
  Spotify and Deezer arms go.
- `PlayableMenuView` preview gating (`.spotify, .apple, .deezer, .plex,
  .subsonic`): becomes Apple, Plex, Subsonic.
- `ServicePreferenceScreen`, `PreferenceScreen`, `Onboard/ServiceRow`,
  `WelcomeScreen`: remove the rows; drop `GroupStorageKeys
  .spotifyMusicTokenID`.
- `Routing/AppRegistry`, `RouterDestination`, `RouterDestinationView`,
  `SheetDestination`: remove the destinations.
- Link handling: `PlayAction/QueueListView` (Spotify/Tidal link parsing and
  the Device fallback), `Widgets/Intents/PlayOnCueIntent` (Spotify links),
  `Mac/DockMenuCoordinator`, `Widgets/RemoteWidget`.
- `Docs/AddingMusicService.md` uses Deezer as the worked example; rewrite
  it around Subsonic or Plex and add the device-playback requirement as
  step zero.
- `Docs/ReleaseCopy-2026.6.md` leads with Spotify in Universal Search,
  playlist management and previews. Release copy for the version that ships
  this needs a "what changed and why" paragraph.
- `Ideas/user-playlists.md`, `auto-dj.md`, `guest-queue.md`: check for
  service lists that name Spotify.

Keep the Sonos-side plumbing that other services share: SMAPI envelope and
credentials (`Packages/MusicSearchKit/.../SMAPI/`), `KeychainTokenRefreshHandler`,
`SonosServiceType` (what Sonos reports installed). Those still serve Apple
Music favorites and the household token path.

## Order of work

Each step is a separate PR that builds and runs on every scheme.

1. **Hide before delete.** Default the six services to disabled in
   `CoreFeatures` and stop `syncEnabledServices` from turning them back on
   from the Sonos household. Filter them out of onboarding, Search, Browse
   and the preference screen. Ships the product change in one small diff,
   and is the rollback point if something is missed.
2. **Playback and links.** Remove the URI arms, the mappers and the link
   parsers, so pasted Spotify/Tidal/Deezer links report "not supported"
   instead of routing to a speaker.
3. **Delete the code.** Remove the enum cases and let the compiler walk
   the remaining switches. One PR per service, largest first (Spotify,
   Tidal, Deezer, SoundCloud, Pandora, Sonos Radio).
4. **Docs and copy.** `AddingMusicService.md`, release notes, the
   App Store description and screenshots.

## Open questions

- **Files** is device-only, the mirror image of the rule. It is a core
  music-player feature, so this note keeps it; if the rule is strictly
  "device *and* Sonos", the Sonos half would be an HTTP server on the device
  that the speaker streams from (the same shape as `DirectStreamProvider`).
- **Music Library** (the speaker's own indexed shares) is the fallback
  `preferredDefaultService` returns when no other service is set up. With
  Subsonic and Files in place the device has its own fallbacks, so it can
  go, but it is the one thing a Sonos-only user has today.
- **Migration for existing users.** Anyone who onboarded with Spotify as
  their default service needs a one-time redirect to Apple Music, Plex or
  Subsonic, plus an in-app explanation. Decide whether step 1 ships with a
  release note only or an in-app banner.
- **Preview clips.** Spotify and Deezer previews were the only previews for
  users without an Apple Music subscription. Nothing replaces them.
