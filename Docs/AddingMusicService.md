# Adding a New Music Service to Cue

This guide walks through every file that needs to change when integrating a new streaming service. Deezer is used as the worked example throughout.

---

## Overview

A new service touches three layers:

| Layer | What changes |
|---|---|
| **MusicSearchKit** | API client, data models, icon asset |
| **SonosKit** | Search/lookup wiring, Sonos URIs, parser, browse service |
| **App** | UI guards, browse screen, service preference screen |

Most UI switches already use `default:` or `service != .unknown` so they need **no changes**. The places that still need manual updates are called out explicitly below.

---

## 1. MusicSearchKit package

### 1a. Add the enum case — `MediaSearchService.swift`

```swift
public enum MediaSearchService: String, Sendable, Codable, CaseIterable {
    // ...
    case myService
}
```

Then add cases to:
- `title` → display name
- `isBrowseSupported` → `true` if you're building a browse screen
- `image` / `iconForMusicService` → add to the `tuneIn, soundcloud, deezer` group if the icon is loaded by `self.title`, or to the `plex, tidal, spotify` group if loaded by `self.rawValue.capitalized`
- `brandColor` → hex brand colour

### 1b. Create the API client — `{Service}API.swift`

Model it on `DeezerAPI.swift`. Key points:
- No auth needed for public endpoints? Use a simple `URLSession` + `JSONDecoder`
- User library endpoints? The Sonos-stored OAuth token is already in the keychain — retrieve it via `KeychainTokenRefreshHandler.shared.getAccessToken(for: .myService)` in `MusicSearchService` and pass it as a parameter
- Auth needed with a separate OAuth flow? See `SoundCloudAPI.swift` for the `TokenRefreshHandler` pattern
- Use `.convertFromSnakeCase` key decoding to avoid manual `CodingKeys` for snake_case APIs:
  ```swift
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  ```
- Use a private `get<T: Decodable>(_:queryItems:)` helper to avoid repetition
- User endpoint helper pattern (pass token as param, add as query item):
  ```swift
  private func authed<T: Decodable>(_ path: String, accessToken: String, index: Int, limit: Int) async -> [T]
  ```

### 1c. Create data models — `Models/{Service}/`

One file per type (track, album, artist, playlist). Use `Decodable` only (never `Codable`) for API responses. Make containers generic:

```swift
struct MyServiceContainer<T: Decodable>: Decodable {
    let data: [T]
}
```

If the API returns `release_date` on albums, add it and expose a `releaseYear` helper — it's used in the subtitle:
```swift
public let releaseDate: String?   // decoded automatically with convertFromSnakeCase
public var releaseYear: String? {
    releaseDate.flatMap { $0.split(separator: "-").first.map(String.init) }
}
```

### 1d. Add the icon asset — `Resources/Media.xcassets/Music Icons/{Service}.imageset/`

- Prefer a **PDF** (vector, scales perfectly at all sizes, no `@2x`/`@3x` needed)
- If using a PNG, put it in the **3x slot** to avoid rendering too large
- Always set `"template-rendering-intent": "template"` and `"preserves-vector-representation": true` (PDF only) in `Contents.json`

---

## 2. SonosKit package

### 2a. Add the enum case — `Models/MusicService.swift`

Add to:
- `CaseIterable` enum declaration
- `init?(service:)` → map from Sonos's string identifier
- **`init(from decoder:)` → the custom forgiving `Codable` decoder at the bottom of the file.** ⚠️ This is easy to miss and silently corrupts data. The encoder is synthesized (it writes the case *name* as a key, e.g. `"deezer"`), but the decoder is hand-written and maps any unlisted key to `.unknown`. If you forget your case here, every value of your service decodes back as `.unknown` after any `Codable` round-trip — drag-and-drop (URI becomes the bare id → Sonos error 804), `CloudStorage` (`playHistory` `OrderedSet` collides → "Decoded elements aren't unique" crash), etc. Add:
  ```swift
  case "myService": self = .myService
  ```
- `name` → lowercase string (used in deep link URLs)
- `title` → display name
- `sonosRawValue` → Sonos service string
- `icon` / `image` → add to the appropriate group (same logic as `MediaSearchService`)
- `brandColor`

### 2b. Token access

Most services whose users authorize through the Sonos app (Apple Music, Spotify, Deezer) already have their OAuth token stored in the keychain by Sonos. Retrieve it via:

```swift
KeychainTokenRefreshHandler.shared.getAccessToken(for: .myService)  // async throws → String?
```

Only add a `GroupStorageKeys` entry if you need to store a *separate* token that doesn't come from Sonos discovery (rare — SoundCloud is the main example because it has its own independent login).

### 2c. Add Sonos URIs — `Models/PlayableContent.swift`

Add cases to three computed properties:

**`uri`** — the `EnqueuedURI` sent to Sonos:
```swift
case (.track, .myService):
    return "x-sonos-http:tr-format%3A\(id)?sid=XYZ&amp;flags=32"
case (.album, .myService):
    return "x-rincon-cpcontainer:000XXXXcalbum-\(id)"
case (.playlist, .myService):
    return "x-rincon-cpcontainer:000XXXXcplaylist-\(id)"
```

**`URIMetadata`** — the `EnqueuedURIMetaData` (DIDL-Lite XML, HTML-entity-escaped):
```swift
case (.track, .myService):
    return "&lt;DIDL-Lite ...&gt;...&lt;desc ...&gt;\(myServiceToken)&lt;/desc&gt;...&lt;/DIDL-Lite&gt;"
```

**`uriRadio`** / **`URIMetadataRadio`** — only if the service supports radio/mix:
```swift
case (.track, .myService), (.songRadio, .myService):
    return "x-sonosapi-radio:radio-track-\(radioID)?sid=XYZ&amp;flags=8300"
```

> **How to get the correct URI values:** Use a packet capture or Sonos app logs while playing content from the service. Look for `AddURIToQueue` SOAP calls — `EnqueuedURI` is the `uri`, `EnqueuedURIMetaData` is the `URIMetadata`.

Add a private token property if needed:
```swift
private var myServiceToken: String {
    GroupStorageKeys.storage?.string(forKey: Defaults.GroupStorageKeys.myServiceMusicTokenID) ?? "SA_RINCONXXXXX_X_#SvcXXXXX-0-Token"
}
```

Also add `deezerWebURL`-style deep link property if you want "Open in {Service}":
```swift
public var myServiceWebURL: URL? {
    guard content.service == .myService else { return nil }
    // build URL from content.type and id
}
```

### 2d. Wire search and lookups — `MusicSearchService.swift`

1. Add a private API instance: `private let myService = MyServiceAPI()`
2. Add to the `search(for:)` switch: `case .myService: fetched = await searchMyService(query: capturedQuery)`
3. Add `private func searchMyService(query:) -> [PlayableContent]`
4. Add `public func lookupMyServiceTrack(with:)`, `lookupMyServiceAlbum(with:)`, etc.
5. Add `internal func makeMyServiceTrackContent(from:)` etc. (used by browse service)

### 2e. Update `SonosService.swift`

Add to three functions:

**`getArtwork(from track:)`** — add a `case (.myService):` that calls your track lookup

**`getTrackInformation(from track:)`** — add a `case (.myService):` returning `(Track.Metadata?, URL?)`

**`contentLookup(id:type:service:)`** — add cases for each content type:
```swift
case (.track, .myService): return await musicSearch.lookupMyServiceTrack(with: id)
case (.album, .myService): return await musicSearch.lookupMyServiceAlbum(with: id)
case (.playlist, .myService): return await musicSearch.lookupMyServicePlaylist(with: id)
```

**`getContent(from url:)`** — add cases for each content type (same pattern)

### 2f. Update the parser — `Parsers/MusicServiceParser.swift`

Three places:

**`serviceLookup`** — map the Sonos numeric service ID:
```swift
case "519": return .myService   // find your service's Sonos ID from SA_RINCONXXXXX
```

**`identifyService`** — URI-based detection for when serviceId is missing:
```swift
if normalized.contains("my-service-indicator") { return .myService }
```
> Order matters — put more specific patterns before generic ones (e.g. Deezer's `playlist_spotify` must come before `spotify`).

**`parse(uri:service:)`** — extract ID and content type from the URI:
```swift
case .myService:
    // parse URI to extract (id, ContentType)
```

**`extractMyServiceID`** — add a regex-based extractor if needed.

### 2g. Register in `SonosThirdParty/MediaServer.swift`

Add to `SonosServiceType`:
- Enum case: `case myService`
- `rawValue`: `"My Service"`
- `allCases`: append `.myService`
- `init(from:)` decoder: `case "My Service": self = .myService`
- `fromServiceId`: `case "519": return .myService`

### 2h. Create the browse service — `{Service}BrowseService.swift`

Only needed if `isBrowseSupported = true`. Model on `DeezerBrowseService.swift`:

```swift
@MainActor @Observable
public final class MyServiceBrowseService {
    public static let shared = MyServiceBrowseService()

    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var recentlyPlayed: [PlayableContent] = []
    public var isLoading = false
    public var isAuthenticated = false

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        isAuthenticated = await musicSearchService.isMyServiceAuthenticated
        guard isAuthenticated else { return }
        // load user data concurrently with withTaskGroup
    }

    public func refresh() async { /* clear state, call load() */ }
}
```

Key points:
- `isAuthenticated` is checked at load time via `KeychainTokenRefreshHandler` — show a "Set up in Sonos app" message in the browse screen when false
- Use `OrderedSet<PlayableContent>` for collections that feed `RouterDestination.playableGridScreen`
- User data methods in `MusicSearchService` take an `offset:` param for pagination and return `[PlayableContent]`

### 2i. Add favorites via Sonos SMAPI (optional)

Services that support liking/favoriting tracks can do so via the Sonos SMAPI protocol if the service's SMAPI endpoint is at a known URL (e.g. `https://api.deezer.com/sonos`). This avoids needing a separate direct-service API call.

**Two credential paths:**
- REST/direct API (e.g. Deezer `/user/me/tracks`): just the OAuth access token — retrieve with `KeychainTokenRefreshHandler.shared.getAccessToken(for: .myService)`
- SMAPI calls: need token + service key + householdId — retrieve with `KeychainTokenRefreshHandler.shared.getCredentials(for: .myService)` and wrap in `SMAPICredentials`

**SMAPI helpers in `MusicSearchKit`:**
- `SMAPICredentials` — typed wrapper for `(token, key, householdId)`
- `SMAPIEnvelope` — builds the SOAP XML body; takes `SMAPICredentials` + `SMAPIAction`
- `SMAPIAction` — enum with `.rateItem(id:rating:)` and `.getExtendedMetadata(id:)` cases (add more as needed)

**Wire in `MusicSearchService`:**
```swift
private func myServiceSMAPICredentials() async -> SMAPICredentials? {
    guard let c = try? await KeychainTokenRefreshHandler.shared.getCredentials(for: .myService) else { return nil }
    return SMAPICredentials(token: c.token, key: c.key, householdId: c.householdId)
}

public func likeMyServiceTrack(id: String) async -> Bool {
    guard let creds = await myServiceSMAPICredentials() else { return false }
    return await deezerAPI.rateItem(credentials: creds, smapiID: id, rating: 1)
}

public func isMyServiceTrackLiked(id: String) async -> Bool {
    guard let creds = await myServiceSMAPICredentials() else { return false }
    return await deezerAPI.isItemLiked(credentials: creds, smapiID: id)
}
```

The `isItemLiked` implementation parses `ISFAVORITE=1` from the `getExtendedMetadata` SOAP response — the exact dynamic property key may differ by service; capture a real response with a proxy to verify.

**Add capability flag on `MusicService`:**
```swift
// MusicService.swift
public var supportsFavoriteTrack: Bool {
    switch self { case .spotify, .apple, .soundcloud, .myService: true; default: false }
}
```

**Wire in `FavoriteMenuButton` and `LikeButtonView`:**
Both already read `service.supportsFavoriteTrack` to show/hide, so no structural change needed — just add the `case .myService:` action in each switch.

### 2j. Handle radio title customisation — `Models/Mapping.swift`

If your service names radio differently (e.g. Deezer uses "Mix {title}"):

```swift
let radioTitle = content.service == .myService ? "Mix \(title)" : title
```

---

## 3. App layer

### 3a. Add browse screen — `Cue/Library/{Service}BrowseScreen.swift`

Model on `DeezerBrowseScreen.swift` (Plex-style list). Key patterns:

- Use `List` with `NavigationLink` rows, not `ScrollView`
- Nav rows use `RouterDestination.playableList(title:showSectionIndex:action:)` with `showSectionIndex: false` — the A-Z index is only useful for alphabetical user libraries, not chart or category lists
- Playlists use `RouterDestination.playableGridScreen` with a `Binding<OrderedSet<PlayableContent>>` from the browse service, and show the first 5 inline:
  ```swift
  ForEach(browseService.userPlaylists.prefix(5)) { item in
      PlayableContentView(item: item)
  }
  ```
- "Recently played" section at the bottom shows up to 10 items as `PlayableContentView` rows
- Show a fallback message (not an error) when `!browseService.isAuthenticated`
- Include `.miniPlayerOnScrollHandler()` and `.contentMargins(.top, EdgeInsets(), for: .scrollContent)`

### 3b. Wire browse screen — `Cue/Library/BrowseScreen.swift`

```swift
case .myService:
    MyServiceBrowseScreen()
```

> Already has a `default:` fallback — only add a case if you need a custom browse UI.

### 3c. Register environment — `Cue/Routing/AppRegistry.swift`

```swift
.environment(MyServiceBrowseService.shared)
```

### 3d. Add to browse picker — `Cue/Library/MediaSelector.swift`

The `contains` allowlist is **hardcoded** — add your service:

```swift
[.apple, .library, .plex, .spotify, .soundcloud, .deezer, .myService].contains(service)
```

### 3e. Service preference screen — `Cue/Preferences/ServicePreferenceScreen.swift`

Only needed if the service has a token that must be stored in `GroupStorageKeys` (e.g. Spotify, Apple Music — where you need to select a primary server when multiple accounts exist). For most services whose token comes straight from Sonos discovery, no change is needed here.

### 3f. Add capability flags — `Models/MusicService.swift`

These flags replace all hardcoded service allowlists in the UI. Add `.myService` to each that applies:

| Flag | Effect |
|---|---|
| `supportsRadio` | Play Radio on tracks, artists (`MenuInfoView`, `PlayableMenuView`, `ArtistDetailView`) |
| `supportsViewArtistAlbum` | View Album / View Artist taps in player and queue (`LargePlayerView`, `MenuInfoView`) |
| `supportsFavoriteTrack` | Like/heart button in player and context menus (`LikeButtonView`, `FavoriteMenuButton`) |
| `supportsFavoriteAlbum` | Save album in context menus (`FavoriteMenuButton`) |
| `hasBrandedRadioBadge` | Stations keep the service icon on artwork instead of the generic `radio.fill` glyph (`ContentArtworkView`). Set it for services with a full-colour badge asset |

No view files need to be touched — they already read from these flags.

### 3g. Add "Open in" link

`OpenInServiceView` reads `item.serviceWebURL`. Two ways to provide it:

**Preferred — populate `content.location` at construction time.** Every `MediaContent` initializer for your service should pass the web URL:

```swift
MediaContent(service: .myService, id: id, type: .track,
             location: URL(string: "https://www.myservice.com/track/\(id)"))
```

This applies to search results, lookup results, browse content, and `getTrackInformation`. Share-sheet parsed content already receives the original URL as `location` from the URL parser.

**Fallback — add a deterministic case to `serviceWebURL` in `PlayableContent.swift`.** Only needed when the URL is constructible from the ID alone (e.g. `myservice.com/track/{id}`) but setting `content.location` everywhere is impractical — for example, to cover the window between app launch and the async `getTrackInformation` completing for a cached track:

```swift
case (.myService, .track): return URL(string: "https://www.myservice.com/track/\(id)")
```

Services whose web URLs require context beyond the ID (SoundCloud needs `user/slug`, Plex needs a server machine identifier) cannot use this fallback and must rely solely on `content.location`.

### 3h. Add URL parser for share sheet — `Packages/SonosKit/Sources/SonosKit/SonosAPI+MusicServices.swift`

```swift
case let .some(host) where host.contains("myservice.com"):
    parseMyService(url: url, path: components.path)
```

Implement `parseMyService` to extract service/type/id from the URL path.

### 3i. Add artist detail loading — `Cue/Search/ArtistDetailView.swift`

1. Add cases to `loadArtistData()` switch
2. Implement `loadMyServiceArtist()`, `loadMyServiceTrackArtist()`, `loadMyServiceAlbumArtist()`
3. When the content ID might come from Sonos (no metadata), look up the track first:
   ```swift
   let artistID: String?
   if let existing = playableContent.metadata?.artistID {
       artistID = existing
   } else {
       artistID = await MusicSearchService.shared.lookupMyServiceTrack(with: playableContent.content.id)?.metadata?.artistID
   }
   ```

### 3j. Add media detail loading — `Cue/Search/MediaDetailView.swift`

Add to `updateTracks()` switch:
```swift
case (.album, .myService):
    newTracks = await musicSearchService.lookupMyServiceAlbumTracks(id: playableContent.content.id)
case (.playlist, .myService):
    newTracks = await musicSearchService.lookupMyServicePlaylistTracks(id: playableContent.content.id)
case (.track, .myService):
    // look up track → get albumID → get album tracks
    let albumID: String?
    if let existing = playableContent.metadata?.albumID {
        albumID = existing
    } else {
        albumID = await musicSearchService.lookupMyServiceTrack(with: playableContent.content.id)?.metadata?.albumID
    }
    guard let albumID else { return }
    // ...
```

---

## Already automatic — no changes needed

These work without modification for any service that uses `service != .unknown`:

- `QueueCellView` — View Album / View Artist buttons
- `PlayableMenuView` — View Album / View Artist (for track/album types)
- `FavoriteMenuButton` — shown only for services you explicitly list
- `SearchScreen` — falls through to `ServiceSearchView` via `default:`
- `BrowseScreen` — falls through to `EmptyView` via `default:` if no browse screen
- `SonosAPI+MusicServices.parse(url:)` — `cue://` deep links auto-work via `MusicService(service:)`

---

## Checklist

```
MusicSearchKit
[ ] MediaSearchService.swift — add case + title + isBrowseSupported + image + brandColor
[ ] {Service}API.swift — API client
[ ] Models/{Service}/ — data models
[ ] Media.xcassets/Music Icons/{Service}.imageset/ — PDF icon

SonosKit / Defaults
[ ] MusicService.swift — add case + all properties + custom init(from decoder:) (⚠️ missing case = silent decode to .unknown)
[ ] GroupStorageKeys.swift — only if service needs a separately-stored token (not Sonos keychain)
[ ] PlayableContent.swift — uri, URIMetadata, uriRadio, URIMetadataRadio, webURL, token property
[ ] MusicSearchService.swift — API instance, search, lookups, user data methods (use KeychainTokenRefreshHandler for token), make* helpers
[ ] SonosService.swift — getArtwork, getTrackInformation, contentLookup, getContent
[ ] MusicServiceParser.swift — serviceLookup, identifyService, parse, extractID
[ ] MediaServer.swift — SonosServiceType case + rawValue + decoder + fromServiceId
[ ] Mapping.swift — toRadio title customisation (if needed)
[ ] {Service}BrowseService.swift — browse service with isAuthenticated, userPlaylists: OrderedSet, recentlyPlayed, load()/refresh()
[ ] MusicService.swift capability flags — supportsRadio, supportsViewArtistAlbum, supportsFavoriteTrack, supportsFavoriteAlbum
[ ] SMAPI favorites (optional) — SMAPICredentials helper, likeXxx/isXxxLiked in MusicSearchService, FavoriteMenuButton + LikeButtonView cases

App
[ ] {Service}BrowseScreen.swift — Plex-style List: nav rows with showSectionIndex:false, inline playlist rows, recently played section at bottom
[ ] BrowseScreen.swift — add case (if custom browse UI)
[ ] AppRegistry.swift — register browse service environment
[ ] MediaSearchService+Sonos.swift — add sonosServiceType mapping case; CoreFeatures.swift — add to preferredDefaultService
[ ] ServicePreferenceScreen.swift — only if multiple-account token selection needed
[ ] content.location — set web URL in all MediaContent initializers (search, lookup, browse, getTrackInformation)
[ ] PlayableContent.serviceWebURL — add deterministic case only if URL is constructible from ID and content.location may lag (e.g. first load from cache)
[ ] ArtistDetailView.swift — load functions + loadArtistData cases
[ ] MediaDetailView.swift — updateTracks cases
[ ] SonosAPI+MusicServices.swift — URL parser for share sheet
```

---

## Adding a direct-HTTP (self-hosted) service

Subsonic is the worked example for services with **no Sonos-side account** —
the user enters a server address + credentials in Cue, and the speakers
stream each track straight from the server over plain HTTP. Jellyfin/Emby
would follow this same path. The playback mechanism is already generic; a new
service only supplies the pieces below.

### How playback works (the parts you get for free)

Wiring a `directStreamProvider` arm (step 2) turns all of this on:

- **Track URIs** are the provider's stream URL, single-escaped for the SOAP
  body (`PlayableContent.uri`).
- **DIDL metadata** uses the local-library shape (`RINCON_AssociatedZPUDN`,
  empty item ids — `-1` radio-style ids are rejected by `AddURIToQueue`),
  with a `&lt;res&gt;` carrying the stream URL, its MIME type
  (`AudioMIMEType`), and `duration="H:MM:SS"` — Sonos can't learn a
  direct-HTTP track's length from the stream, and without the attribute the
  player has no progress bar.
- **Containers** (album/artist/playlist) have no Sonos-browsable URI, so
  `SonosService` expands them into their tracks before queueing — single
  items and lists (Discography, play-all) alike — via
  `MusicSearchService.containerTracks(for:)`.

### Stream-URL requirements (`DirectStreamProvider`)

- **Deterministic** — rebuilt URLs must match earlier ones, so queue rows
  survive relaunches and artwork caching stays keyed to one URL.
- **Self-authenticating** — the speaker fetches with no session; carry a
  token in the URL, never the raw password.
- **Extension hint** — Sonos classifies plain-HTTP queue items by the file
  extension it finds in the URL and rejects extension-less ones with UPnP
  error 804. If the endpoint has no extension in its path, append a trailing
  ignored parameter (Subsonic uses `ext=.flac`-style).
- **Transcoding** — the protocol's `streamURL(for:fileExtension:destination:)`
  takes a `StreamTranscoding.Destination` (`.speaker` for the Sonos URI,
  `.device` for on-device playback, downloads and the playback cache; `nil`
  for the original file). Honor the user's `StreamTranscoding` choice for a
  destination and make the extension hint the *transcoded* suffix — the
  speaker is handed what arrives, not what's on disk. `StreamTranscoding`
  already downgrades Opus to MP3 for speakers (Sonos can't decode Opus).
  Keep `previewURL` the original file: it's the stable URL caching keys off,
  and the setting can change under it — `PlayableContent.playbackStreamURL`
  rebuilds the device stream at play time.
- Reachability caveat for users: the *speakers* dial the URL, so it must be
  reachable from the LAN — a VPN-only hostname the phone can resolve won't
  play.

### Checklist

```
MusicSearchKit
[ ] {Service}API.swift — client with credentials in the keychain (see
    SubsonicAPI's SecretsCache pattern), conforming DirectStreamProvider
[ ] Models/{Service}/ — data models

SonosKit
[ ] MusicService.swift — enum case + all properties + custom init(from
    decoder:) (standard checklist above), plus arms in directStreamProvider
    and streamsFullTrackPreview
[ ] MusicServiceParser.swift — identifyService detection for the service's
    stream-URL shape + track-id extraction (see the /rest/stream handling)
[ ] MusicSearchService.swift — search/lookups + a containerTracks(for:) arm
[ ] SonosService.swift — getArtwork / getTrackInformation / contentLookup

App
[ ] Management sheet (server/username/password + ping test — see
    SubsonicManagementView) + SheetDestination case + AppRegistry case
[ ] MediaSearchService+Sonos.swift — isConfiguredInCue and managementSheet
    arms (these drive the Services rows, not-connected copy, and the
    failed-to-queue alert's tap action)
[ ] Browse screen + service surfaces per the standard checklist above
```
