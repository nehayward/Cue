# Changelog

Developer-facing record of changes per version. More detailed than ReleaseNotes.md — includes the what and why, not just the what. Use this as source material when writing App Store release notes.

---

## 2026.7

### Album art crossfade stutter fix
- Fixed the player artwork crossfade hitching the whole player on song changes. `ArtworkView` drove the fade with a persistent `.animation(.smooth, value: displayImage)` modifier keyed on the `UIImage` instance: every back-to-back load at a track boundary (Sonos proxy URL first, then the CDN URL) re-triggered and interrupted the fade, and the implicit animation was free to animate *layout* of the artwork — which renders three times at once (main art plus the full-screen blurred background copies in `LargePlayerView`, one under an 80pt blur), forcing expensive full-screen re-renders mid-fade.
- Reworked as an identity-swap `.transition(.opacity)` inside a `ZStack` (outgoing and incoming art overlap in place), animated only by an explicit transaction in the new `setImage(_:fade:)` helper — `withAnimation(.smooth)` when fading, `Transaction.disablesAnimations` for instant swaps. Unrelated body re-evaluations (playback ticks, mute toggles, layout changes) can no longer start or restart a fade, and loads that return the image instance already on screen are skipped.
- Behavior preserved: the `shouldFade` snapshot is still taken when the artwork URL changes, so a slow load can't fade in after a user skip. Queue taps and natural track advances crossfade; next/previous and speaker switches stay instant.
- New `isBackground` mode on `ArtworkView`, used by the blurred background copies (`BackgroundView` / `BackgroundViewCatalyst`): skips the badge overlay, rounded-corner clip, shadow, and alarm tracking — all invisible under the blur but previously still rendered on every frame of a crossfade. Also made `defaultFadeDuration` a `let` (was needlessly `@State`).

### S1 household discovery + Connect-by-IP fixes
- S1-only players (ZP100, ZP80, older Play:5s…) were invisible to the entire household model: `SonosAPI.getHouseHoldID` only parsed `CurrentMuseHouseholdId` from `GetZoneGroupAttributes`, a Muse (S2) API field S1 firmware never reports. The empty id made every path drop the device — Bonjour discovery (`performDiscovery`), the Households scan (`discoverHouseholds`), and the known-IP reconnect race in `getGroups(useCache:)` — so a split S1/S2 home could add its S2 system but never (re-)add the S1 one, and adopting the S2 household made the S1 player disappear for good
- `getHouseHoldID` now falls back to `http://<ip>:1400/status/zp` → `<HouseholdControlID>` when the Muse id is absent. That endpoint exists on every firmware generation, and its `Sonos_xxx` value matches the Muse id's pre-dot base (which the method already strips to), so S1 and S2 devices of one household resolve to a single consistent id across both paths
- `ConnectByIPScreen.validateIP` fired an uncancelled probe per keystroke; a slow response for a prefix of the address (e.g. `…1.1` while typing `…1.10`) could land after the full address's probe and flip `deviceFound` back to false — the reported "green tick, then No Sonos system found". The probe task is now cancelled on each edit and stale results (text no longer matching) are discarded
- The screen also had no way to adopt the typed IP — its rows only list `sortedRooms` of the already-active household. Added a "Connect to This Device" button (shown once `deviceFound`) that runs `setStaticIP(ip:)`, which pins the legacy IP, resolves + adopts the household (now works for S1 via the fallback), and reconnects
- Added parser tests: `HouseholdControlID` extraction from a `/status/zp` payload, and `parseHouseID` returning empty for an S1 `GetZoneGroupAttributes` response (documents why the fallback exists)

**S1 fix ported to SonosKitMini (Clic Mini + Watch)**
- `SonosKitMini` is a zero-dependency package and can't import `SonosKit`, so it carries its own `getHouseHoldID` — which had the identical Muse-only parse. The failure was worse there: `getAllHouseholdsIPs` does `guard !householdID.isEmpty else { continue }`, so an S1 speaker's IP was dropped outright and the household never appeared in the Watch's list at all. Watch's `preferredHouseHold` also stayed nil for an S1 pick, so its "Current" tick never lit
- Same `/status/zp` → `HouseholdControlID` fallback. Normalising the two sources matters — the Muse id has a trailing `.yyy` that `/status/zp` lacks, so comparing them raw would file the S1 and S2 halves of one household under two ids — but the trim can't be applied at the source: `getHouseHoldID` also feeds `getSystem` → `toConfig` → `SonosPlayerConfig.householdId` → `connectAndSubscribeToGroup`, which needs the full dotted form, so trimming there would have silently killed live group-topology events for every S2 household in Clic Mini and the Watch. Split into two calls instead: `getHouseHoldID` returns the device's value verbatim (WebSocket, `getSystem`), and `householdIdentity` returns it trimmed for comparison and de-duplication (`getHouseID` → `clic.household`, `getAllHouseholdsIPs`). S1 players have no Muse WebSocket to subscribe to, so their missing suffix costs nothing
- The identity form differs from what was previously written to `clic.household`. Safe: nothing in SonosKitMini or the Watch compares a stored household id against a fetched one (`preferredHousehold` has only a getter/setter, and Watch's sole read is a `!= nil` check) — unlike `SonosKit.performDiscovery`, which does match on equality

**Legacy `sonos_ip` mirror follows the pinned speaker**
- `mirrorLegacyIP` wrote `activeHousehold.lastKnownIP`, which the reconnect race rewrites to the first responder — so the main app used the chosen speaker while Clic Mini and the Watch (which read `sonos_ip` directly, via `NSUbiquitousKeyValueStore`/`UserDefaults`) followed a different one. New `mirroredIP` prefers `preferredSpeakerIP`, gated on that IP being in the active household's `knownIPs` so a pin from another home can't aim them at a system the main app isn't on. `pinPreferredSpeaker`/`clearPreferredSpeaker` both re-mirror
- Ordering matters in `setStaticIP`: `setPreferredSpeaker` re-mirrors, and the new IP isn't in the household's `knownIPs` until `adoptHousehold` runs — so mirroring before `pinLegacyIP` resolved back to the *old* address, and if the household lookup then failed there was nothing left to correct it, stranding the legacy key and breaking the discovery-independent bootstrap `pinLegacyIP` exists to provide. The legacy pin now goes last, leaving the hand-entered IP standing on that path
- `pinPreferredSpeaker`/`clearPreferredSpeaker` collapsed into one `setPreferredSpeaker(_:)` — clearing was only ever "set to empty", and two methods meant two copies of the change-guard and re-mirror
- Kept the legacy key rather than removing it: Mini and Watch reach it through storage only, and it now carries the correct resolved address, so the mirror is the whole integration. Full removal would mean duplicating `SonosHousehold` into SonosKitMini, decoding `sonos_known_households` from `NSUbiquitousKeyValueStore`, and rewriting the Watch's three write sites — deferred, not needed for correctness. Note `clic.household` lives in `UserDefaults.standard`, so household preference has never synced to the Watch

**Connectivity screen reframe (`ConnectByIPScreen`)**
- The screen was three controls that all funnel into `setStaticIP(ip:)` — the IP field's Connect, `Set Priority Device` (which is just `priorityDevice()` + `setStaticIP`), and tapping a room row — presented as if unrelated, and narrated with three different vocabularies ("Connected to…", "Assigning Priority to…"). Restructured around the one question they all answer: which speaker Clic connects through. All three now report through `announceConnection(to:)` with identical wording
- `Set Priority Device` became a "Choose Best Speaker" row with its selection rule as an inline caption. Kept deliberately as an *action*, not a persistent "Automatic" mode with a checkmark: `setPriorityDevice()` resolves and pins one IP once — nothing re-runs it when the network changes — so a sticky "Automatic" indicator would claim behavior the app doesn't have
- The instructions told users to open the Sonos app and hunt for an IP while the list directly below already showed every speaker's IP. They're only useful when that list is *empty*, so they moved into a collapsed `DisclosureGroup` ("Can't find your speakers?") that auto-expands on appear when `sortedRooms` is empty — the one case where manual entry is the only way forward
- Speaker rows now use the `HouseholdScreen` idiom (trailing green checkmark for the active one) instead of radio-style circles, which implied a selection group but fired actions; the room section is hidden entirely when empty rather than rendering a headed, empty section
- Added the missing `navigationTitle("Connectivity")` — the screen had none, so it pushed with a bare back chevron, and its Preferences entry point says "Connectivity" while the type says "ConnectByIP"
- Preview now uses `.withEnvironments()`; it previously injected only `SonosService` while the screen also reads `AlertService`. Dropped unused `discoveredIPs`/`isSearching` state
- IP field validation reworked. The trailing `xmark.circle.fill` sat directly beside the system clear button — two red-ish circle-with-x glyphs reading as two controls — so wrongness is now a red fill + border on the field itself. The accessory slot shows only a probe spinner (`isProbing`) or the green found check, and the "valid but unverified" hollow check is gone: it looked like success while nothing had been found
- Fixed the speaker selection not persisting — the tick flashed onto the tapped row and reverted. Two independent causes, both now closed:
  - The tick read `sonos_ip`, the legacy mirror. `setStaticIP` writes it via `pinLegacyIP`, then its own `load(useCache:)` re-enters the `getGroups` race with `cachedIPVerified = false`; the winning IP calls `recordHousehold`, which rewrites `lastKnownIP` and re-runs `mirrorLegacyIP()` over the key. The user's pick was overwritten by whichever speaker replied first, usually within the same second
  - `prioritizedIP()` — the resolver behind every system-wide lookup (artwork via `prioritizedAlbumArtIP`, `LibraryBrowseService`, favorites, playlists, alarms) — never consulted any stored selection at all. It re-derived a winner from the live `groups` by model-name sort each call, so even a persisted pick would not have changed which speaker Clic used
- New `sonos_preferred_speaker_ip` CloudStorage key, written only by explicit user action (`pinPreferredSpeaker`, called from `setStaticIP`). Kept separate from `legacyIP`/`lastKnownIP` on purpose: those mean "an address that reaches this household" and are *supposed* to follow the race, so overloading either would reintroduce the same overwrite. `prioritizedIP()` now returns the pin first, gated on a room with that IP existing in the current `groups` so a pin from another household falls back to the heuristic instead of stranding every lookup
- Unified the two automatic heuristics and dropped the "Choose Best Speaker" button. There were two different "pick the best speaker" implementations: `priorityDevice()` (ethernet first, then model; keeps rooms whose `info` hasn't loaded) behind the button, and `prioritizedIP()`'s own copy (computes an ethernet ordering, then *discards* it by re-sorting on model name alone; drops `info`-less rooms) on the automatic path everything else used. So the default pick silently ignored the wired preference, and the button existed to apply a better algorithm by hand. `prioritizedIP()` now falls through to `priorityDevice()`, making the automatic behavior the good one and the button redundant
- Automatic is now a row in the same picker rather than a separate action, ticked when the pin is empty. With `sonos_preferred_speaker_ip` in place, "no pin" is a real persistent state that can carry a tick — the earlier objection to an Automatic *mode* (nothing re-ran the pick, so a sticky indicator would have lied) no longer applies, since the resolution happens per `prioritizedIP()` call. It's also the only route back after choosing a speaker; new `useAutomaticSpeaker()` / `clearPreferredSpeaker()`, and `automaticSpeakerChoice()` names the speaker it currently resolves to so the row isn't abstract
- Success haptic through the app's existing `HapticManager` (`.notification(.success)`), fired after a choice lands rather than on tap so a failed pick doesn't buzz. Speaker rows, Automatic, and manual Connect all use it
- `validateIP` now clears `deviceFound` when starting a probe. Editing a found address (`…1.10` → `…1.100`) previously left it true until the new probe returned, so Connect stayed enabled for an address nothing had answered on and would pin a dead IP into both the preference and the legacy mirror
- The Automatic tick keys off `isUsingAutomatic`, which mirrors `prioritizedIP()`'s gate (a pin whose speaker isn't in the current system is ignored) rather than `preferredSpeakerIP.isEmpty`. After a household switch the stored pin is still set but no longer applies, so the old check left the list with no tick at all while the app was in fact running on Automatic
- `setPriorityDevice()` now has no callers in-repo but is kept: it's public SonosKit API and the only entry point that both picks and adopts in one step
- Error state is driven by a new `showsInvalidIP` (`isPartialIP`), not `!isValidIP`. `isValidIP` is a full-match regex, so every prefix on the way to a complete address — `192.`, `192.168.` — was styled as an error mid-keystroke. `isPartialIP` accepts anything that can still *become* valid: ≤4 dot-separated groups, each ≤3 digits and ≤255, only the last allowed empty. The probe itself still gates on the full-match `isValidIP`
- Connection badge on each speaker row: "LAN" when `Room.ethernetEnabled`, "Wi-Fi" when `wifiEnabled`, nothing when the device reports neither. Both come from ZoneGroupState (`EthLink` / `WifiEnabled`), which older S1 players can omit entirely — falling back to "Wi-Fi" on a missing `EthLink` would assert the opposite of the truth for a wired ZP100, the exact call this badge exists to get right. Surfaces the same signal `priorityDevice()` already sorts on
- Wrapped the room list in a titled Section with a footer explaining what tapping does and why LAN matters; the rows were previously bare in the `Form` with nothing saying they were tappable
- Fixed the Set Priority Device caption clipping its wrapped line: `.listRowInsets(EdgeInsets())` zeroed the horizontal margins too, running the text flush to the row edge. Now keeps 20pt leading/trailing, with `.fixedSize(horizontal: false, vertical: true)` and leading alignment so it wraps fully instead of being centered by the enclosing `VStack`
- Rewrote the "How to find IP" steps: capitalized LAN, split finding the address from entering it, and corrected the example from `192.167.1.100` (not a private range — a typo for `192.168.…`) and "i.e" to "e.g."
### Radio → queue transition fixes
Playing a queue item while a radio station (e.g. Sonos Radio) was active could leave the player stuck on the station: no progress bar, station caption still up, and in the worst case playback itself never switched. Four related fixes in `SonosService`:

- The same-`unique` reconcile paths in `load()` and `updateTrackInformation` now also reconcile `duration` (gated on non-zero, mirroring the artist/album gates). Sonos reports `TrackDuration 0:00:00` while a stream is still opening right after a transport switch; the first-pulse 0 was stored on the track and never corrected — every later pulse early-returned on matching `unique` — so `PlaybackView` (which hides the slider when `duration.isZero` and ranges it `0...duration`) kept the progress bar hidden for the whole song.
- New `markSwitchedToQueue(group:)` — called after every `SetAVTransportURI` to `x-rincon-queue` (`seek(trackNumber:on:)`, `queuePlayable`'s non-queue branch, `switchToQueueInput`). Sets `playbackService = .queue` and clears `radioStation` immediately instead of waiting on the next GetMediaInfo pulse, so the station caption drops right away and the queue's now-playing highlight (`GroupRoom.isNowPlaying`, which requires `.queue`) lights on the tapped row. The pulse still re-verifies against the device and corrects if the switch didn't stick.
- `seek(trackNumber:on:)` now asks the device for the live playback service instead of trusting the cached `group.playbackService` (falling back to the cache if the device doesn't answer). A stale `.queue` — possible after backgrounding or when another controller changed the source — skipped the transport switch entirely, so the `Seek(TRACK_NR)` no-oped against the radio stream and playback genuinely stayed on the radio.
- `updateGroupCheckTVMode` applies the `playbackService` update synchronously (the task-group closure is already `@MainActor`) instead of through a fire-and-forget nested `Task`, which could let a stale pre-switch `.radio` reading land *after* the optimistic `.queue` write and resurrect the station caption for a pulse.

### Authorization-aware Services preferences
- `ServicePreferenceScreen` now splits services by what's authorized on the user's Sonos system. Discovered services keep their show/hide toggles (with the existing Spotify/Apple Music multi-account menus); the rest move to a dimmed "Available with Sonos" section whose rows deep-link to the Sonos app (`sonos://`, App Store fallback) to sign in. While discovery hasn't returned anything (cold keychain read, no system found) every service keeps its toggle so nothing gets hidden by a race; pull-to-refresh re-runs discovery.
- Services authorized in Sonos but unsupported by Clic (Pandora, SiriusXM, Bandcamp, …) render as dimmed informational rows, matching onboarding's `ServicesStep`; truly unknown services show as a footer count with a "Help us add support" link.
- New `MediaSearchService.sonosServiceType` extension (`MediaSearchService+Sonos.swift`) is the single Clic ↔ Sonos service mapping. `CoreFeatures.syncEnabledServices` and onboarding's `ServicesStep` both derive from it — which also fixes Sonos Radio being missed by the onboarding sync (it was in `ServicesStep`'s hand-rolled list but not `CoreFeatures`'). `preferredDefaultService` gains a Sonos Radio fallback before Library.
- New `CoreFeatures.disableUnauthorizedServices(from:)`: whenever the Services screen gets a fresh non-empty discovery result, services no longer authorized in Sonos are switched off. Disable-only — it never re-enables, so a manual "off" survives. Search/browse react live since all surfaces observe `CoreFeatures.shared`.
- Plex management folded onto its row in the services list: whole cell tappable (`.onTapGesture`; the trailing toggle keeps its own touches) with trailing "Manage" / "Sign In" secondary text doubling as the Clic-side auth indicator. The separate "Personalized Services" section is gone; the conditional "Override Spotify" button moved to a "Troubleshooting" section shown only when a single Spotify account is discovered; "Can't find the Service here?" is now plain footer text at the bottom; the Now Playing toggle moved up into its own section.

### Pandora via SMAPI
Adds Pandora as a browsable, searchable, playable service over the Sonos SMAPI protocol — the same integration path as Sonos Radio, using the household's stored loginToken plus the controller deviceId.

- New `PandoraAPI` (`MusicSearchKit`): SOAP-only SMAPI client with `getMetadata` (browse) and `search`, sharing Sonos Radio's lock-guarded `refreshAuthToken` dedup pattern; auth faults (`tokenRefreshRequired`, `AuthTokenExpired`, …) trigger a single shared refresh + one retry, and rotated token/key pairs are persisted back through `KeychainTokenRefreshHandler` so cold starts skip the refresh round trip.
- New `SMAPIAction.getMetadata(id:index:count:)` in `SMAPIEnvelope` — the generic SMAPI browse call, reusable by any future SMAPI service.
- `MusicSearchService`: `pandoraContext()` resolves credentials (keychain, service-registry id `60423`) and the SMAPI endpoint (memory → persisted cache → live `ListAvailableServices` discovery → `https://sonos.pandora.com/v2.1`, the SecureUri from the captured descriptor list). `pandoraBrowse(id:)` exposes raw SMAPI containers/items; `pandoraStations(matching:)` searches the `"all"` category — the combined artist/track/station search the official controller runs, returning playable station seeds (`SF:…` ids).
- Playback (`PlayableContent`): station URI `x-sonosapi-radio:<ST%3A…>?sid=236&flags=32` with `000c0020`-prefixed item id, `audioBroadcast` class, stream `<res>`, and the `SA_RINCON60423_X_#Svc60423-0-Token` cdudn — verified against a Proxyman capture of the official controller's `SetAVTransportURI`. The controller sends the household's Pandora account serial in place of the `0` there, but the generic serial plays fine (the speaker resolves the account from the service id); the real serial is the Pandora `MediaServer` UDN verbatim, which would only matter for a household with two Pandora accounts.
- SMAPI shape note (from the capture): Pandora returns stations as `mediaCollection` elements with `itemType` "program" / `canPlay` true, so the browse service classifies stations by `canPlay` rather than mediaMetadata-vs-mediaCollection; root has a single `myStations` container (plus a nested "Stations (A-Z)").
- `MusicServiceParser`: sid `236` ↔ `.pandora` in `serviceLookup`/`identifyService` (plus `Svc60423` XML and "pandora" URI hints); station id recovered with the shared `x-sonosapi-radio` extractor.
- New `PandoraBrowseService` + `PandoraBrowseScreen`: root `getMetadata` containers become sections ("My Stations", "Browse", …) with preview grids and "see all" lists, section caching via `MemoryFileCache`, and stale-refresh error banners — mirroring the Sonos Radio browse screen.
- Browse revalidates after 5 minutes rather than trusting a session-long `hasLoaded`. Stations appear on the account without Clic doing anything: playing a search result creates one (search returns `SF:` seeds, browse returns `ST:` stations — playing a seed is how Pandora "adds" a station), as does the Pandora app or another controller. The cached sections stay on screen while the refetch runs.
- Enum plumbing: `.pandora` added to `MediaSearchService` and `MusicService` (titles, icons, brand color, forgiving decoders), `MediaSearchService.sonosServiceType` mapping (so onboarding + Services settings pick it up automatically), `CoreFeatures.preferredDefaultService`, and a full-colour vector `Pandora.imageset` in Music Icons (template-rendered only on the player artwork badge, via `MusicService.artworkBadgeIcon`).

### Pandora thumbs up / thumbs down
- New `ThumbsRatingView`, shown by `LikeButtonView` in place of the heart for Pandora. Two buttons rather than a toggle: a thumb is feedback sent to the *station*, and a thumb down tells Pandora to stop playing the track — it isn't "unfavorite", so it can't share the heart's on/off semantics. SMAPI exposes no way to read back an existing rating, so the selection is local state for the current track and clears on track change, matching the Pandora app.
- `PandoraAPI.rateItem` goes through the same refresh-and-retry path as browse/search: `performParsed` and the new `rateItem` both call a shared `performRaw`, so an expired token is refreshed once and the call retried rather than silently failing.
- Thumbs down skips, matching Pandora: the station stops playing a thumbed-down track, so the view calls `next` after the rating lands. Gated on success — a failed call shouldn't cost the user the song they're on.
- `MusicSearchService.thumbsUpPandoraTrack(trackID:)` / `thumbsDownPandoraTrack(trackID:)` wrap it. The rating targets the *track*, not the station: `pandoraSMAPITrackID(from:)` derives the SMAPI id from the playing stream id (`VC1::ST::ST:<station>::TR:<track>::0::RINCON_…:<n>.mp3` → same minus the extension), covered by `PandoraRatingTests`. The rating values (1 / -1) follow the SMAPI convention rather than an observed request — the capture this integration was built from never exercised a thumb, so that pair is the thing to correct if thumbs come back rejected.

### Pandora SMAPI auth: account-scoped householdId
- Every Pandora SMAPI call was failing with `Failed to reauth device id` — browse, search and rating alike — and `refreshAuthToken` faulted the same way, so the session could never recover. Pandora scopes its session to the *account*, not the household: the official controller sends `<householdId>Sonos_<id>_<serial></householdId>`, where the serial is the account segment of the Pandora service UDN (`SA_RINCON60423_X_#Svc60423-62fe75eb-Token`). Apple and Spotify get the bare id from `GetHouseholdID`, which is why no other service needs this.
- New `KeychainTokenRefreshHandler.serverUDN(for:)` returns the UDN of the account backing a service's credentials (same primary-server selection as `getCredentials(for:)`), and `accountSerial(fromUDN:)` extracts the middle segment. `pandoraContext()` appends it, falling back to the bare id when the account can't be read or the serial is already present, so it can't corrupt a working session. Covered by `PandoraRatingTests`.

### Pandora misidentified as Plex mid-station
- A Pandora station would flip the whole player to Plex — orange heart, Plex lookups — partway through listening. `identifyService`'s Plex heuristic (`decodedURI.contains(":3:")` ) ran *before* the `sid=236` check, and Pandora's per-track stream id carries a `::<sequence>::` field that increments per track: on the 4th track it reads `::3::`, which contains `:3:`. Intermittent by construction, and it also mis-set the id extractor and every service-keyed lookup downstream.
- The `sid=` parameter is authoritative, so the Pandora and Sonos Radio sid/account checks now run ahead of the positional heuristics; only the weaker `"pandora"` name hint stays below `:3:`, so a Plex path containing "pandora" still resolves as Plex. `MusicServiceIdentificationTests` pins sequences 0–5, the station-URI form, and that Plex's own heuristic still works.

### Radio stations as alarms / saved-queue adds
- Pandora (and Sonos Radio, TuneIn) stations already work as alarm sources — `createAlarm` sends `content.uri` + `content.URIMetadata`, both of which the per-service `(type, service)` cases already populate, and nothing gates alarm search by content type. No change needed there.
- Fixed the *saved-queue* path, which is separate: `alarmURIMetadata` (used only by `addToPlaylist` for non-track content, despite the name) hardcoded the cdudn to Apple's token for Apple and Spotify's for **everything else**, so a Deezer/Tidal/Plex album or any radio station added to a Sonos playlist carried the wrong service account. New `PlayableContent.serviceToken` resolves the right one per service, keeping the Spotify default only for services with no account of their own.
- `containerClass` gained `.radio`/`.liveRadio`/`.songRadio`/`.artistRadio` cases returning `object.item.audioItem.audioBroadcast`; that path previously emitted an empty `<upnp:class>` for every station.

### Clic Mini panel corners and Liquid Glass
- Fixed square corners on the Clic Mini HUD (`HudWindowManager`) and menu bar window (`StatusBarMenuWindowController`). Both rounded their background with `layer.cornerRadius` on a `.behindWindow` `NSVisualEffectView`, which only clips what the *layer* draws — the blurred backdrop is composited by the window server against the view's rectangular bounds, so it kept square corners. Over a dark desktop those corners read as shadow and went unnoticed; over a light one they showed as bright square edges around the rounded card. New `NSVisualEffectView.applyRoundedCornerMask(radius:)` sets a cap-inset rounded-rect `maskImage`, which is what actually clips the backdrop — and with the existing `invalidateShadow()`, the drop shadow follows the rounded shape too.
- New `PanelBackground.wrap(_:frame:cornerRadius:bordered:)` (`ClicMini/PanelBackground.swift`) is the single decision point for both windows' backgrounds: `NSGlassEffectView` on macOS 26, the corner-masked `PanelEffectView` blur below that. ClicMini deploys to macOS 15.1, so both paths stay — this is additive, not a replacement.
- The mask image and the hairline border are fallback-only; glass clips its own backdrop and draws its own edge. `PanelEffectView`'s border is now appearance-adaptive (white 12% dark / black 10% light) — the old fixed white hairline vanished against the light material, which is what left the panel edge looking undefined in light mode.
- Both windows now set `hasShadow = !PanelBackground.drawsOwnShadow`, dropping the window shadow on 26 since glass already separates itself from the desktop.
- Behavior note: the menu bar window's hosting view has `translatesAutoresizingMaskIntoConstraints = false` with no constraints ever added — it was just `addSubview`'d into the effect view. `wrap` preserves that exactly on the fallback path (it skips frame/autoresizing for constraint-driven content), but `NSGlassEffectView` pins its `contentView`, so on macOS 26 the hosting view now fills the window.

### Live Activity dismissed by a volume tap
- Tapping a volume number in the Live Activity from another app dismissed the Live Activity outright. `SetVolumeIntent` (and the relative-volume intents) set the volume and then call `LiveActivityManager.refresh()`. A `LiveActivityIntent` runs in the app's process, so when Clic isn't already running iOS launches it in the background purely for that intent — and in that fresh process `SonosService.groups` is still empty, because `getGroupCoordinatorWithRoom` fetches groups over the network but only `load()` assigns `service.groups`. `refresh()` read the empty list as "this room no longer exists" and ran its fallback, which ended **every** activity with `.immediate`.
- `refresh()` now loads the topology when `groups` is empty, and returns without touching any activity if it's *still* empty. An unreachable system (off Wi-Fi, speakers asleep, load failed) is indistinguishable from a removed room, so the safe reading is to leave the activities alone and let the next refresh correct them.
- The missing-group fallback ends only the activity whose room is absent, instead of the whole set — one stale room could previously take every other room's Live Activity down with it.
- The per-speaker fetch failure path now `continue`s to the next activity rather than `return`ing out of the loop, so one unreachable coordinator no longer stops the remaining activities from updating.
- `PlaybackIntent` never showed this: it calls `createActivity(id:)` first, which already does `load(useCache: true)`. The fix lives in `refresh()` rather than in each intent so every caller — volume, mute, night mode, speech enhancement, sleep timer — is covered by one guard. The added load only runs when `groups` is empty, so the in-app refresh path (foreground/inactive scene changes) is unaffected.

---

## 2026.6

### Playlist management across music services
First-class playlist management for Apple Music, Spotify, Plex, and Deezer alongside Sonos.

**Add to playlist**
- New `AddToPlaylistSheet` (replaces the old single-track Sonos `AddToPlaylistMenu`): share-sheet-style, segmented between the track's own service and Sonos, with multi-select + one Done, search, a "New Playlist" action, a "Recently Added" quick-pick (top 3), and a confirmation toast that deep-links to the target playlist
- Wired into every track-menu surface: `PlayableMenuView` (search/library/detail), `MenuInfoView` (Large Player), the queue menus (`QueueCellView`/`QueueScreen`/`UpNextContentView`), and the macOS native `UIMenu` (now lists the track's service playlists + Sonos)
- One-tap "Add to last playlist" shortcut (`AddToLastPlaylistButton`) with the destination service icon, gated to service-compatible tracks; last-used playlist (id/title/service) and recents tracked centrally in `LastPlaylist`
- `MusicSearchService` gains create/add/remove/delete wrappers + service-agnostic dispatch (`addToServicePlaylist`/`removeFromServicePlaylist`/`reorderServicePlaylist`); `SpotifyAPI`/`PlexAPI`/`DeezerAPI`/`AppleMusicAPI` gain the underlying mutation endpoints

**Edit playlists** (`MediaDetailView` + `PlaylistEditCoordinator`)
- Swipe-, menu-, and bulk-remove; drag-to-reorder; delete playlist — all optimistic with rollback on failure. Sonos and streaming edits both route through `PlaylistEditCoordinator`, which owns the track list so edits survive view rebuilds
- Undo/Redo for add/remove via an owned undo/redo stack on the coordinator (replaces `UndoManager`): one stack drives the tap-to-undo toast, the iOS ⌘Z / ⌘⇧Z keyboard shortcuts, and a native Catalyst Edit ▸ Undo/Redo menu. Sonos edits aren't undoable (its add appends — no positional re-add)
- Editing gated to playlists the user can actually modify: Spotify via owner/collaborative from a `fields`-filtered `/playlists/{id}` lookup (cached user id + membership fallback); Deezer via per-playlist owner check; Plex always (server-owned); Apple never

**Create playlists**
- Create playlists per service from the browse screens ("+") and the add sheet, including **empty** playlists for Apple, Spotify, Deezer, Plex, and Sonos. Plex empty creation posts `type=audio` with no seed (with a title-based fallback when the create response omits the new id)
- `DeletePlaylistConfirmationView` and `NewPlaylistView` follow the app's sheet pattern — top ✕ dismiss, single prominent action button

**Service coverage:** Sonos (full); Spotify / Plex / Deezer (add, remove, reorder, delete, create); Apple Music (add + create only — no public remove/reorder API). Deezer reorder is intentionally excluded (its reorder endpoint takes a full track-id list, unsafe for a paginated playlist); Deezer writes require the `manage_library` OAuth scope.

**Catalyst menu**
- Native Edit ▸ Undo/Redo wired to the playlist editor through the app delegate / responder chain (`PlaylistUndoMenuBridge`); enable/disable follows the undo stack via `canPerformAction`
- Removed the auto-injected AutoFill / Start Dictation / Emoji & Symbols items from the Edit menu (`NSDisabledDictationMenuItem` / `NSDisabledCharacterPaletteMenuItem` + `.autoFill` builder removal)

**Fixes**
- Removing a track from a Spotify playlist now deletes only the selected occurrence, not every copy. The remove request now sends the track's playlist position (`positions`) instead of just its URI, which Spotify treats as "remove all occurrences." Multi-select removals run sequentially (highest position first) so the positional indices stay valid. Plex was already safe (unique per-row id); Deezer's API only removes by track id, so a duplicated Deezer track still removes all copies (upstream limitation).
- Adding a Spotify album with more than 50 tracks now adds the whole album. `addToSpotifyPlaylist` pages through the album's tracks (50 per page) instead of taking only the first page, and posts them in chunks of 100 (the add-tracks request cap) — previously the overflow was silently dropped while still reporting success.
- "Recently Added" in the Add-to-Playlist sheet is now keyed by service (`<service>:<id>`), matching the selection logic, so a recent id from one service can no longer surface a same-id playlist in the other segment.
- Deezer "Add to Playlist" now lists only playlists you own. `userPlaylists(for: .deezer)` filters `/user/me/playlists` to `creator == me` (new `deezerEditablePlaylists()`), mirroring Spotify — previously followed playlists were offered as targets and the add silently failed. Browse still shows all playlists.
- Service playlist browse grids gain a toolbar refresh button (`PlayableGridScreen`), so creates/deletes can be pulled in on Mac/Catalyst where SwiftUI pull-to-refresh doesn't fire.
- `PlaylistEditCoordinator`'s undo/redo history is extracted into a pure, unit-tested `UndoRedoStack` (SonosKit) covering push/undo/redo, redo invalidation on a fresh edit, and clearing.
- Viewing a Plex artist from a track (e.g. "View Artist" on a song in `MediaDetailView`) now shows the artist's albums. `ArtistDetailView.loadPlexArtistData` always populates `albums` and picks the first non-empty category (`albumType = .firstAvailable(...)`) like the direct-artist path — previously the track path passed `setAlbums: false` and never selected a category, so the Albums section rendered with the picker stuck on an empty "Album" tab.

### Queue shuffle animation
- Tapping the shuffle button in the queue now animates the Up Next and Full Queue lists reordering into their shuffled positions instead of snapping. Move and delete also animate as a side effect.
- Reworked queue row identity: rows are now keyed by `content.id` + *occurrence index* (the Nth copy of a song in the loaded window) via `keyedByOccurrence()`, instead of `trackID` (`content.id` + position). Occurrence keys are unique (handles duplicate songs) and stable under reorder, so SwiftUI animates rows *moving* rather than cross-fading. The shuffle action is now just an animated `withAnimation` swap of the fetched order — no identity-preserving workaround needed.
- List selection, context menus, and delete now resolve the selected occurrence keys back to tracks (`tracks(forKeys:)`); scroll-to-now-playing resolves the row's occurrence key (`occurrenceKey(forPosition:)`) since `ScrollViewReader` matches `ForEach` identity.
- Shuffle/repeat state (`group.playMode`) is now loaded in `onAppear` for both queue modes; previously it was only fetched in the full-queue view's task, so the shuffle/repeat buttons didn't reflect the speaker state when opening the default Up Next view. Their active color is also now driven via `.tint` on the button (iOS toolbars override `.foregroundStyle` on the label with the bar tint, so the highlight didn't show on iOS).
- Now-playing row highlight now compares queue position via a shared `GroupRoom.isNowPlaying(_:)` (gated on playing from the queue) instead of `currentTrackID`. `currentTrackID` was only populated in full-queue code paths, so the playing track never highlighted in the default Up Next view; the position check works in both modes and live-updates as the track changes. Both the row number and the cell use the one helper so they can't drift. The first-load scroll sentinel is now a plain `hasScrolledToNowPlaying` flag (the old `currentTrackID` string value was never read).
- No-op when the returned order is unchanged, so there's no regression for sources that don't reorder `Q:0`.

### Deezer integration
- Added `DeezerAPI` client in `MusicSearchKit` — no auth required, hits public `api.deezer.com` endpoints
- Full search: tracks, albums, artists, playlists (concurrent `async let` in `MusicSearchService.searchDeezer`)
- Browse screen (`DeezerBrowseScreen`) powered by `DeezerBrowseService` showing Top Tracks, Albums, Artists, and Playlists from Deezer charts
- Correct Sonos URIs verified via SOAP capture:
  - Track: `x-sonos-http:tr-flac%3A{id}?sid=2&flags=32`
  - Album: `x-rincon-cpcontainer:0004006calbum-{id}`
  - Playlist: `x-rincon-cpcontainer:0006006cplaylist_spotify%3Aplaylist-{id}`
  - Radio/Mix: `x-sonosapi-radio:radio-track-{id}?sid=2&flags=8300`, title prefixed "Mix {title}"
- Deezer service token auto-detected and stored from Sonos server discovery in `ServicePreferenceScreen`; token read from `GroupStorageKeys.deezerMusicTokenID` at enqueue time
- `MusicServiceParser`: service IDs "2", "519", "250" → `.deezer`; `playlist_spotify` URI check ordered before generic `spotify` check to avoid misidentification
- `SonosServiceType.deezer` added to `MediaServer.swift`; `CoreFeatures.syncEnabledServices` maps `.deezer → .deezer`; included in `preferredDefaultService` fallback chain
- View Album, View Artist, Open in Deezer, and Play Radio (Mix) all wired up — radio available from track context menu, artist page, and large player
- `SonosAPI+MusicServices`: parses `deezer.com/{locale}/{type}/{id}` share URLs, strips 2-letter locale prefix
- `DeezerLinkResolver` (`MusicSearchKit`): resolves the Deezer *app's* short "smart" links — `link.deezer.com/s/{token}` (Branch.io) and legacy `deezer.page.link` / `dzr.page.link` (Firebase) — which carry no type/id in the path. Follows the redirect with a desktop User-Agent, then scans the final URL / interstitial HTML for the canonical `deezer.com/{type}/{id}` link. Wired into `SonosService.getContent(from:)`, so sharing from the Deezer app (not just the website) now works in PlayAction and everywhere else
- Added `Docs/AddingMusicService.md` — comprehensive guide and checklist for integrating future services

### Song previews
- The Apple Music / Spotify track menu gets a "Preview Song" action that plays the clip while the menu stays open (`menuActionDismissBehavior(.disabled)`); a leading-swipe "Preview" action on list rows is the other entry point
- Preview audio runs through `AudioPlaybackService.preview(url:)` using `.ambient` + `.mixWithOthers` so it layers over other audio and respects the silent switch; an explicit call always (re)starts the clip from the beginning, so a track can be re-previewed after it's already played
- `PlayableContentView` (list rows) and `PlayableContentRowView` (browse grids) show a bottom progress bar that fills as the clip plays plus a stop affordance — tapping an auditioning row/cell stops it. The bar is gated on `isPreviewing` so stopping removes it instantly instead of animating its width back to zero
- Only shown for tracks that actually carry a `previewURL` (mapped from Apple Music `previewAssets` and Spotify `previewUrl`)
- Dropped the auto-preview-on-menu-open behaviour and its `AppStorageKeys.autoPreviewSongs` setting. SwiftUI exposes no reliable "menu was presented" signal, so every trigger we tried (`onAppear`, `.id(UUID())`, `.task(id:)`) either missed presentations or re-fired on re-render and replayed the clip right after the user stopped it. Preview is now driven entirely by the explicit button + swipe; also removed the unused `SongPreviewCard` peek view
- Previews now play through `.playback` + `.duckOthers` (was `.ambient` + `.mixWithOthers`), so a deliberate preview tap is audible even with the silent switch on — matching Apple Music. Previews also stop automatically when the app is backgrounded
- Plex previews: Plex has no short clip, so a Plex preview streams the full track from the user's server via a token-authenticated stream URL (built from the media part key), played progressively with `AVPlayer` (`preview(url:streaming:)`) rather than downloading the whole file first
- Tapping a cell to stop an auditioning preview now fires a `buttonPress` haptic
- Apple **library** track previews: library songs and library-playlist/album tracks now preview too. Apple's library API omits previews (a catalog-only attribute), so the library song / playlist-tracks / album-tracks requests now pass `include=catalog` and read the catalog relationship's `previews` into `AppleLibraryItem.previewURL` — one request, no extra round-trips

> **Note — `include=catalog` is a reusable unlock.** Pulling each library item's full catalog resource inline (no per-item lookups) opens up a lot of future potential beyond previews. Any catalog-only attribute — full/animated artwork, genres, ISRC, editorial notes, audio variants (lossless / Dolby Atmos), popularity, accurate release dates — and any catalog relationship (artists, albums) can now be surfaced for **library** content the same way: add the field to `AppleLibraryItem.Attributes` (or a relationship) and read it off the included `catalog`. Worth reaching for whenever a library screen needs richer data than the library API returns.

### Line-in support detection
- `Room.supportsLineIn` now prefers the device-reported `LINE_IN` capability from the `/info` endpoint (`DeviceInfo.capabilities`) instead of relying solely on model-name matching — authoritative across firmware/models
- Tightened the fallback model keywords used when capabilities aren't reported: the bare `"Play"` substring matched Play:1/Play:3/Playbar/Playbase (no line-in), wrongly surfacing the "Switch to Line In" action in `MenuInfoView`
- `"Play:5"` kept; the 2026 portable "Play" matched by exact last-token comparison so its siblings are excluded
- `"Era"` left broad (Era 100/100 SL/300 all support line-in via the USB-C adapter); `"Move 2"`, `"Five"`, `"Amp"`, `"Connect"`, `"Port"` unchanged

### Sonos library pagination
- Library browse lists made a single fixed-size `Browse` request and relied on a one-shot `.task`-fired indicator that never re-triggered, so libraries larger than one page were silently truncated — Albums stopped ~mid-"D" (first 500); Artists only looked complete because there were fewer than 500
- `LibraryBrowseService.updateSongs` / `updateAlbum` / `updateArtists` / `updateGenres` now fetch one page at `offset` and return whether a full page came back (`count >= pageSize`); callers request the next page at `offset == current count`, deduped via `updateOrAppend`. All `update*` methods are `@MainActor` so observed-state writes stay on the main actor
- `PlayableContentList`: replaced the one-shot `.task` load-more indicator with an `.onAppear` sentinel gated by a single in-flight `isLoading` flag plus `hasMoreContent`, so pages load as the user nears the bottom without racing the initial load; a bottom spinner shows only while a next page is actively fetching
- `GenreListView`: added a guarded near-the-end paging trigger (`isLoadingMore` / `hasMoreGenres`); `FolderBrowseView`: added offset paging for Sonos folder contents via `browseFolder(folderID:offset:)`, Apple Music folders keep their single-request path
- `LibraryBrowseScreen`: Imported Playlists load-more closure now forwards `offset` to `updateImportedPlaylists(offset:)` instead of discarding it (was always re-fetching page 0)
- Alphabetical grouping moved out of `PlayableContentList` (where a computed dictionary was re-grouped once per section header and again per letter subscript — O(letters × items) every render) into cached `LibrarySection` arrays on `LibraryBrowseService` (`albumSections` / `artistSections` / `playlistSections`), recomputed only when the underlying set changes; the view now renders the prebuilt sections, so non-data re-renders do zero grouping work. Playlist deletion routed through `removePlaylist(id:)` so the cache stays in sync

### Spotify performance
- `SpotifyAPI` now passes `market=from_token` on search, track/album lookups, saved tracks/albums, playlist, and artist top-tracks/albums endpoints. With a market specified Spotify returns its slim payload — a single `is_playable` flag replaces the deprecated `available_markets` array (~185 country codes on every track and album object) — so responses are much smaller with no change to availability
- Playlist endpoints additionally use the `fields` filter: `/playlists/{id}` drops the inlined first-100 `tracks.items` (callers only read name/owner/images/count), and `/playlists/{id}/tracks` returns only `total,items(uid,track)` — exactly what `SpotifyPlaylistsFullContainer` decodes. `SpotifyArtistAlbums.AlbumItem.availableMarkets` became optional since market-aware responses omit the key
- Halved the album browse-list page size (50 → 25) in both `SpotifyLibraryScreen` and `SpotifySearchScreen` so the first batch paints sooner; 25 stays clear of `PlayableListView`'s "within 10 of the end" prefetch trigger so paging stays smooth

### Spotify album loading fixes
- Spotify album detail (`MediaDetailView`) now keys its load on `content.id` via `.task(id:)` and runs a `loadInitialTracks()` that resets pagination from a clean slate, so a reused view re-fires for a different album instead of showing the previous album's tracks. Cancelled first-page loads no longer mark the view permanently "loaded" with no tracks, and cancelled loads bail before appending so a stale response can't pollute a freshly-reset list
- Spotify albums over 50 tracks now paginate: decode the tracks paging metadata (`total`/`next`/`limit`/`offset`) on `SpotifyAlbumDetails` and page through `offset` (Spotify caps album track pages at 50), stopping at `total`; a `supportsPagination` helper drives both the prefetch trigger and the offset guard
- Fixed the Spotify Albums browse list shrinking/reshuffling on re-entry: the offset-less fallback used `playlists.count` instead of `albums.count`, and the `offset == 0` refresh branch pruned `albums.prefix(10)` while re-fetching only 5, deleting already-paged albums. Prune only within the window actually re-fetched (`prefix(newAlbums.count)`) and page `/me/albums` in 50s. New browse additions surface at the top and stay stable on revisit instead of resorting

### iPad / Catalyst sheet + inspector presentation
- Fixed sheets self-dismissing on iPad/Catalyst when the inspector (Queue) was open. `withInspector` drove `inspector(isPresented:)` with a `.constant` binding — in compact widths (Split View / Stage Manager / narrow Catalyst windows) the inspector falls back to a sheet presentation, and when the system dismissed it SwiftUI couldn't record that in a constant, so it re-presented the inspector and tore down the sheet the user had just opened. Now uses a real two-way binding that clears `router.inspectorSheet` on dismissal
- `.sheet`/`.fullScreenCover` were applied inside `.inspector` (modifiers apply inside-out), so an inspector restructuring between column and sheet presentation (rotation, size-class change, Catalyst resize) rebuilt the subtree hosting the sheet and dismissed it. `withInspector` is now applied first so sheets are hosted outside it. The inspector is also stashed and restored across compact collapses and size-class transitions
- Fixed the queue inspector not following the selected group, and deduped the Sonos topology subscription while sharing a single `MusicSearchService`

### Plex now-playing highlight
- Fixed the now-playing row highlight never matching for Plex in `MediaDetailView` (and the search/library rows). The highlight compared the coordinator's `track.trackID` against `content.id.removingPercentEncoding`, but Plex now-playing trackIDs are percent-encoded (`clientID%3A3%3AratingKey` — the parser re-encodes the colons via `.urlPathAllowed`), so an encoded-vs-decoded comparison never matched. Both sides are now decoded before comparing — a no-op for services whose IDs carry no percent-encoding (Apple/Spotify/Tidal/Deezer)

### Multiple households & instant multi-network reconnect
Clic now models every Sonos system it has connected to as a `SonosHousehold` and reconnects by racing known addresses against Bonjour, so moving between networks (home ↔ a friend's house) is instant once a home is known.

**Model & storage**
- New `SonosHousehold` (`id`, `lastKnownIP`, `knownIPs: Set<String>`, `name`, `lastConnected`) persisted as `sonos_known_households` in `@CloudStorage` (iCloud-synced). Custom `init(from:)` migrates older records that predate `knownIPs` by seeding it from `lastKnownIP`
- `cachedIP`/`lastKnownIP` are now derived from the active household (single source of truth). The old `sonos_ip` key is read once for first-launch migration and otherwise kept as a **write-only mirror** (`mirrorLegacyIP`) so external readers — Clic Mini, the Watch app, the Connect-by-IP indicator — keep following the active system
- `activeHousehold` = the pinned `preferredHouseHold` when set, else the most-recently-connected home

**Reconnect race (`SonosService.getGroups`)**
- When the session-cached IP isn't yet verified, races a deduped `Set` of every known household's IPs plus a Bonjour discovery task; first responder wins and `cancelAll()` tears down the losers (`URLSession.data` is cancellation-aware). `cachedIPVerified` gates the fast path so steady-state polls stay a single request
- Identity is always resolved from the responding device (`getGroups` + `getHouseHoldID` fired concurrently via `async let`) — an IP is never treated as a stable household id (DHCP reassignment, colliding `192.168.x.x` across LANs). Only a verified, still-known household is adopted; anything else falls through to Bonjour
- A 400ms grace window lets a still-reachable *preferred* household win over other reachable systems before widening, so a second Sonos on the same LAN can't hijack the manual selection
- `invalidateVerifiedConnection()` is called on foreground (`ClicApp` scenePhase) so a network change while backgrounded re-races instead of stalling on a now-stale IP

**Household management (`SonosService`)**
- `switchHousehold`, `removeHousehold`, `renameHousehold`, `discoverHouseholds(includeRemoved:)`. Removal writes a synced `sonos_removed_households` blocklist honoured by `recordHousehold`/`adoptHousehold`/`performDiscovery`, so a deleted home isn't re-adopted by the pulse, a scan, or a widget/intent extension process (the blocklist lives in the same synced store as the household list, not device-local `UserDefaults`). Removing the active home also `clearDevices()` to stop the pulse
- `performDiscovery`'s terminal widening fallback is guarded by `Task.isCancelled` so a cancelled Bonjour arm can't clobber the race winner's (or a switch's) selection
- Manual Connect-by-IP (`setStaticIP`/`setPriorityDevice`) resolves and adopts the household at the entered IP through the model — the sole bootstrap on Bonjour-blocked networks
- Concurrent browses (reconnect discovery vs. the Households scan) are serialized by a bounded, cancellation-safe `waitForExclusiveBrowse` gate so they don't reset each other's shared `NWBrowser`/`allIPs` state

**Households screen** (`HouseholdScreen`)
- Shows stored homes instantly, then lazily enriches each row with its speaker names and an S1/S2 badge (`getGroups(with:)` + `deviceInfo(for:)` per home). Tap to switch, long-press context menu or swipe to rename/remove, toolbar button to rescan the current network (which un-blocks a previously-removed reachable home)

### Search relevance overhaul (SearchRanking)
- Ranking extracted from `MusicSearchService` into a pure, unit-tested `SearchRanking` engine (SonosKit) — the old scoring counted an in-order character subsequence, so "Love" and "Lyrics of Vengeance" tied for the query "love", and popularity carried the dominant weight (0.5)
- Tiered text matching: exact (1.0) > prefix (0.9) > whole-word substring (0.8) > all query words present (0.75, typo-tolerant words discounted) > mid-word substring (0.55) > length-penalized subsequence (≤ 0.4). Normalization is case-, diacritic- and punctuation-insensitive ("beyonce" == "Beyoncé", "dont" == "Don't", "Mr. Brightside" == "mr brightside")
- Typo tolerance via bounded Levenshtein per word (1 edit for 5–7 letters, 2 for 8+, none shorter — "love" must not match "dove"); titles also scored with version suffixes stripped ("Love Story (Taylor's Version)" counts as "Love Story" at 0.97)
- Weights: text 0.7 (dominant — popularity can never carry a weak match past a strong one), quality 0.25 (Spotify/Tidal popularity or Plex/library `userRating`, whichever is present), small type nudge 0.05, recently-played boost 0.1 (IDs injected by the app from `PlayHistoryService` — SonosKit holds no app state), recency boost up to 0.05 for releases under 2 years (`albumYear`)
- Exactly one artist — the best-scoring, genuinely matching one — gets the top-slot bonus (0.2); a flat artist boost walled tracks/albums behind runs of same-named artists (searching "dua" showed ten artists named "Dua" above every track)
- The top artist's albums inherit its popularity when the service reports none (Spotify's search API omits album popularity), so the focused artist's albums surface beside their tracks
- Score ties keep the service's API order instead of sorting alphabetically — preserves Apple's own relevance ordering (MusicKit reports no popularity)
- Dedup is exact-identity only (`id-title-subtitle`); fuzzy cross-source dedup was tried and reverted — collapsing per-section Plex copies could leave zero songs once the per-section library filter excluded the surviving copy, and cross-service copies should stay user-selectable
- First regression tests for ranking: `SearchRankingTests` in SonosKitTests (tiers, weights, typo tolerance, top-artist, recency, dedup)

### Multiservice search (Universal Search)
- The search service menu (`MediaServiceMenu`) is now one checkmark list — pick up to three services to search together (e.g. Library + Apple Music), the first selected acting as the primary. Toggles stay open via `.menuActionDismissBehavior(.disabled)`; selections only apply while enabled in Settings; TuneIn stays single-service (a radio directory doesn't merge into catalog results)
- The selection persists as ONE ordered primary-first list (`AppStorageKeys.selectedSearchServices`, typed `SelectedSearchServices` wrapper in SonosKit owning all the selection rules — max 3, TuneIn exclusivity, primary promotion, never empty, Settings pruning, defensive dedup — covered by `SelectedSearchServicesTests`). This replaced the split `mediaService` + `searchAlsoServices` keys mid-branch — deliberately not migrated, the selection resets once and users re-pick; onboarding and the bootstrap analytics read/write the new key
- The toolbar button shows the selected services as up to three brand-colored icons side by side (`ServiceIconRow`); overlapping/masked-seam "avatar pile" variants were tried and reverted — the mask's compositing glitched and clipped while the row animated between selection sizes
- The "Settings…" entry (service preferences sheet) is restored at the bottom of the menu — it was dropped in the checkmark-list rewrite
- Disabling a service in Settings now deselects it in search: extras already dropped out via read-time filtering, but a disabled primary stayed selected (icon lingering in the toolbar, search still querying it). `validateSelectedServices` promotes the first enabled extra, else falls back to the first enabled service — live while the Settings sheet is up (`CoreFeatures` is observable) and on appear
- `MusicSearchService.search` accumulates multi-provider results into one merged, re-ranked list as each provider completes (previously last-writer-wins overwrote `results` per provider); merged results render through the generic `ServiceSearchView` as a single ranked list, single-service searches keep their per-service views
- TuneIn results now go through ranking too — safe now that ties preserve the API's order (exact station-name matches float, the rest stay put)

### Per-service sections key on membership, not the primary
- The empty-query screen's per-service sections only showed for the *primary* service — Spotify's browse section and Apple's playlists vanished when that service was a multi-search extra. `SearchEmptyStateView` now takes the full selected set and shows each section when its service is anywhere in the selection
- The merged results view now carries the Plex library-selection prompt (`PlexLibrarySelectionView`, self-gated to Plex-authorized-but-no-library) when Plex is among the searched services — previously only the dedicated Plex view showed it

### Filter chips cover every searched service + Spotify artist radios
- The filter chips were driven by the primary service alone, so Apple as a multi-search *extra* lost its Radio and Library chips. `FilterSelection.filters(for:)` now unions the filters of every searched service, and `FilterView` keys off the full selected set
- Spotify search results now include radio: Sonos can start a Spotify artist radio, so the top two artist matches surface an "Artist Radio" row (`toPlayable.toRadio`), mirroring Apple's radio stations in results
- The Radio filter chip now also matches artist/song radios (`.artistRadio`/`.songRadio`), not just stations

### Plex library filter in multi-search
- The per-library Plex filter button was hidden during a multi-service search because the merged list ignored it. It now shows whenever Plex is among the searched services, and the merged list honors it: `filteredByPlexLibraries` (shared with `PlexSearchView`) drops Plex rows outside the chosen libraries while other services' rows pass through. (The button was already glass via `accentGlassButton`; glass on the type filter chips was tried and reverted — it read oddly in the masked chip row)

### Stable search results across navigation
- Merged multi-service results were appended in provider-completion (network) order; since the ranking's tie-break preserves input order, equally-scoring items (an artist's many same-ranked albums) reshuffled every republish. Provider results are now keyed per service and the merged input rebuilt in a fixed service order before each sort, making the ranking reproducible
- Multi-service results now publish once, after every provider finishes, instead of re-ranking the visible list on each provider's completion — a slower service's copy of the artist joined the grouped cluster at the top and shoved everything down a row seconds after results appeared. Providers run concurrently, so the wait is only the slowest one (the loading spinner covers it)
- Each provider's fetch races an 8s deadline (`MusicSearchService.withTimeout`): an unreachable service — the Sonos library or a LAN Plex server while on cellular or a foreign network — would otherwise sit in TCP connect for up to 15s and, with single-publish, hold every other service's results hostage. A timed-out provider contributes nothing

### Review fixes (timeout/caching interactions)
- A single-service provider timeout no longer leaves the *previous* query's results on screen as the new query's answer — the timed-out search clears to the "No Results" state instead
- `search(for:)` now reports whether every provider answered; the search screen only memoizes a query as "completed" when it did, so a partial result (timed-out provider) retries on the next visit instead of being cached forever
- The search task id and the skip-identical-search guard now share one key (`searchTaskKey`), built from the *effective* enabled-filtered service set with separators — disabling/re-enabling an extra service in Settings re-runs the search (raw stored extras didn't change the old id), and adjacent-component key collisions are impossible
- The skip guard no longer skips the task's side effects: recently-played ranking IDs and the Sonos playlist refresh stay fresh on every pop-back
- The "No Results" empty state and keyboard navigation now apply the Plex library filter like the rendered list does — a fully-filtered list shows the empty state instead of a silent blank, and arrow keys can't select hidden rows
- `PlexMetadata.toPlayable` album mapping now carries `albumID`, so artist-detail/browse Plex albums get the per-edition artwork key too (search-only before — the duplicate-edition wrong-art bug persisted on artist pages)
- Album subtitles never render "0 songs": the six hand-rolled pluralizations collapsed into one `Int.songCountLabel` extension property (internal to SonosKit) that drops missing/zero counts and pluralizes via automatic grammar agreement (`^[…](inflect: true)`) instead of hand-rolled branches

### Search speed + complexity cleanup
- An Apple search no longer ranks the same items three times over: `searchLibraryAppleMusic` and `searchAppleMusic` return unranked (their only caller, `searchApple`, ranks the combined list once) — the dominant per-keystroke CPU cost on the main actor
- `SpotifyAPI.albums(ids:)` fetches its 20-id chunks concurrently instead of serializing round-trips; `SearchRanking.pinArtistRadios` bails before any allocation when a sort carries no radios (most services'), and the artist passes reuse cached normalized names
- `FilterView` takes one `services` set (the redundant `selectedService` binding and empty-set fallback are gone) and only reassigns the chips when the set actually changes — a no-op toggle no longer wipes keyboard selection and re-animates the row. Play History passes `[]`, restoring its default chips (the Spotify-radio chip had leaked in). Dead `appleFilters` removed (`filters(for:)` is the single source)
- Service enablement reads use `CoreFeatures.isEnabled(_:)` instead of constructing a Binding per check; the byte-identical `#available(iOS 26)` toolbar branches collapsed; `OverlappingServiceIcons` renamed `ServiceIconRow` with its dead `overlap` property removed (the icons deliberately sit side by side); `PlexParser`'s four copies of the token-signed image-URL construction folded into one helper
- Navigating back from a detail re-fired the search `.task(id:)` (push cancels it, pop restarts it — same id) and re-ran the whole search, re-streaming providers into the visible list. `SearchScreen` now remembers the last *completed* query+services key and skips the identical re-search, keeping the on-screen results untouched

### Plex duplicate editions distinguishable (bitrate + per-edition artwork)
- A Plex library holding the same album from several rips (FLAC vs 320 kbps) rendered them as identical rows with identical artwork. Track rows now show the media bitrate after the codec ("FLAC • 1411 kbps") — `PlexParser` reads the `Media` element's `bitrate` into `PlexTrack`
- Album rows show their track count ("12 songs") — the standard-vs-deluxe distinction — via the album's `leafCount`; Plex puts no media info on album containers, so count + artwork + year are the available album-level distinguishers
- Track count on album rows extends to the other services too: Apple catalog albums (`Album.trackCount`), Apple library albums (`attributes.trackCount`), Spotify albums (`total_tracks`, newly decoded on the simplified search objects), Tidal (`numberOfTracks`), and Deezer (`nb_tracks`, newly decoded)
- A UIKit-presented service menu (transparent `UIButton` + `.keepsMenuPresented` + `updateVisibleMenu`) was tried to keep the menu open across toggles and reverted: Catalyst renders `UIMenu` as a native Mac menu that ignores `keepsMenuPresented` and draws the asset images full-size, so it only helped iOS — the menu stays a SwiftUI `Menu` of Toggles with `.menuActionDismissBehavior(.disabled)`
- Servers that omit detail from `/hubs/search` responses (a track's `Media` element, an album's `leafCount` — the same omission that used to drop tracks entirely) never surfaced any of this — `searchPlex` now fills the gaps with one batch `/library/metadata/{id,id,…}` lookup (`PlexAPI.batchMetadata(ratingKeys:)`) covering every track and album that came back without
- The artwork cache key (`PlayableContent.imageKey`) was album title + artist, so every edition shared one cached image — whichever edition's art was fetched first showed on all of them. Plex artwork is now keyed by the album's unique `ratingKey` (`PlexAlbum` carries its own key as `albumID`, matching the track mapping's `parentRatingKey`), so each edition displays its own art while a track still shares its album's cache entry

### Plex hearts in search results
- `PlexParser` now reads the `userRating` attribute for tracks and albums (`PlexTrack`/`PlexAlbum` → `PlayableContentMetadata.userRating`), so the heart `PlayableContentView` already renders appears in Plex search rows — and rated tracks feed the ranking's quality signal

### Search "No Results" empty state
- `SearchScreen` shows the standard `ContentUnavailableView.search(text:)` when a query finishes loading with no matching results (`!isLoading && currentFilteredResults.isEmpty`) — previously the list was simply blank. Gated on `isLoading` so it never flashes while provider results are still streaming in

### Plex search parsing resilience
- `PlexParser` required 13 attributes per track (`Media` audio details, `Part` file, `parentThumb`, all rating keys, `librarySectionID`, …) and silently dropped any track missing one — servers that omit optional detail from `/hubs/search` responses returned zero songs while albums/artists still showed. Tracks, albums, and artists now require only `title` + `ratingKey` (all the Sonos play URI needs); everything else is optional with the track's own `thumb` as an artwork fallback
- `PlexTrack.container`/`file` (never consumed) and the `parentRatingKey`/`grandparentRatingKey` keys are now optionals; Plex subtitles skip empty components instead of rendering dangling "•" separators

### Search ranking review hardening
- Word-boundary detection now checks every occurrence via padded containment instead of only the first range — "Supermarket Market" earns the whole-word tier for "market", and top-artist album attribution no longer misses later whole-word occurrences
- Normalization folds width too (fullwidth "ＡＢＢＡ" matches "abba"); the query is normalized once per sort instead of ~4× per item
- Top-artist floor lowered to the typo tier (0.6) so a misspelled artist query ("beyonse") still crowns the artist — safe now that the bonus scales with artist popularity

### Apple Music Top Results as the popularity signal
- MusicKit exposes no popularity, so Apple results ranked on text tiers alone. `searchAppleMusic` now requests `includeTopResults = true` and grants Apple's editorial Top Results descending synthetic popularity (90, 85, …) via `PlayableContentMetadata.replacing(popularity:isExplicit:)` — Apple's picks rank like the other services' hits, and an Apple artist in Top Results qualifies for the full top-artist bonus (the bonus scales with popularity)
- Apple already supported the other new signals: `contentRating` drives the explicit badge on songs *and* albums, and `releaseDate` feeds the new-release boost

### Spotify album popularity + explicit badge
- Spotify's search API returns simplified album objects with no `popularity` and no explicit flag, so albums ranked on text alone and sat below every popular track ("frozen" buried the soundtrack; a same-named song outranked "Radical Optimism"). `searchSpotify` now enriches result albums through the batch `/v1/albums?ids=` endpoint (new `SpotifyAPI.albums(ids:)`, chunked at Spotify's 20-id cap): `popularity` feeds the ranking's quality signal and the explicit badge is derived from the album's tracks (`containsExplicitTracks`)
- Multi-service search: artist copies share their best-known popularity across services (an Apple `Dua Lipa` with no popularity borrows the Spotify copy's) so every copy levels up and lands above its self-titled albums; `groupArtists` clusters all matching artists at the top of a merged search, and album inheritance runs once per album

### Plex onboarding + automatic connection

**Onboarding Plex step** (`PlexStep`)
- New onboarding step, inserted after the services screen when Plex is among the user's authorized Sonos services (`WelcomeScreen.Step.plex`); signs into Plex, then for a fresh setup auto-selects the first server with a music library and its first library so Plex works out of the box
- Library rows show a cluster of up to three overlapping circular artist thumbnails, fetched in the background after the list renders (`PlexAPI.getArtists(server:sectionKey:limit:)`, a server-specific fetch that doesn't depend on the selected library) with white separator rings
- Shared `PlexConnectionPicker` — a segmented Auto / Remote / Local control with a sliding pill and a floating "Recommended" badge on Auto — used by both `PlexStep` and `PlexManagementView` (replacing that screen's stacked cards and ~237 lines of dead code); `OnboardingEvent.viewedPlex` added

**Automatic (hybrid) connection** (`PlexAPI` / `PlexServer`)
- New `.auto` `ConnectionPreference`, now the default: `resolveBaseURL(for:)` races the server's local + remote connections with `/identity` probes and uses whichever responds first (fast LAN at home, remote away); `.local` / `.nonLocal` force a single connection. Relay connections deprioritized in `PlexServer.nonLocalURIs`
- Resolved connection cached per server and reused across `getMusicLibraries(server:)`/`getArtists`; browse path caches via `getPlexServer`. All connection-cache state (`plexServer`, `resolvedBaseURL`, `resolvedBaseURLByServer`) guarded by an `NSLock` (`withCacheLock`) so concurrent browse/self-heal tasks don't race, while keeping `getBaseURL` synchronous
- `loadData` self-heal: on a connection-level failure it re-resolves the retained server (no extra plex.tv round trip) and retries once against a *different* connection (local↔remote failover via `URL.rebasing(to:)`), only when re-resolution yields a different URL. Request timeouts added (10s fetch, 4s probe)
- Search-result image URLs built from the connection the data was actually fetched over (`parseXML(..., baseURL:)`) so artwork loads over the same host as the results under `.auto`

### Music library share location in Preferences
- New `SonosService.libraryShare()` browses the `S:` container (the same `getLibraryItems(IP:type:)` call the Library → Folders screen uses) with `RequestedCount = 1` and returns the first configured share path (e.g. `//nas/Music`)
- `PreferenceScreen` fetches the share in its existing `.task` and shows it as a single-line caption (middle-truncated) under the "Refresh Sonos Library" label — hidden when no share is configured or no speaker has been discovered yet
- Motivated by Sonos's S1 desktop controller being Intel-only (unusable once Rosetta goes away): the share path is now visible in Clic, alongside the existing local `RefreshShareIndex` re-index action

### Arc Ultra speech enhancement controls
Full speech level control for Sonos Arc Ultra across all surfaces.

- New `SpeechLevel` enum (`off=0, low=1, medium=2, high=3, max=4`) with `title: String` and `isActive: Bool` in both SonosKit and SonosKitMini (separate modules, no shared dep)
- `TVSettings` / `SonosTVSettings` gain `speechLevel: SpeechLevel` and `speechIsActive: Bool` computed properties; `speechIsActive` reads `speechLevel.isActive` for Arc Ultra (`speechEnhanceEnabled != nil`), `dialogLevel` for standard soundbars
- `SonosService.setArcUltraSpeechLevel` writes `SpeechEnhanceEnabled` and `DialogLevel` EQ values in parallel via `async let`; level `0` sets enabled=false only, levels 1–4 set both
- `SpeechEnhancementMenu` shared component (SonosKit targets) with `compact` and `showLabel` params replaces triplicated Menu blocks in `TVModeViewCell`, `LargePlayerView`, and `MiniPlayerView`
- Live activity / widget references updated from `dialogLevel` → `speechIsActive` so Arc Ultra active state highlights correctly
- `SetSpeechEnhancementIntent` (existing toggle shortcut) detects Arc Ultra via `try?` on `getTVSettings(isArcUltra:true)` — throws SOAP 500 on non-Arc-Ultra, nil result → standard path
- New `SetSpeechLevelIntent` with `SpeechLevelOption: AppEnum` for direct level selection on Arc Ultra
- ClicMini: TV tile buttons match Watch style (44pt square tile, icon + label, system background); Arc Ultra speech level uses `Button + popover` instead of `Menu` (macOS `borderlessButton` style strips label backgrounds); state refreshed via explicit `getTVSettings` call after each action
- Watch: buttons use `VStack(icon + label)` with `.tint` for active state; TVSettings fetched on scene activation (not only when `x-sonos-htastream` track fires); Arc Ultra cycles Off→Low→Medium→High→Max on tap
- `SonosMiniService.updateDevice` made `public`; `api.deviceInfo(IP:)` uncommented; `loadWatch` fetches device info in parallel for all devices so `isArcUltra` resolves correctly from `modelDisplayName`
- `DiscoveryInfo` struct added to SonosKitMini (was only in SonosKit)

### TV Dialog Sync (audio delay)
- Sonos exposes lip-sync delay via RenderingControl `GetEQ`/`SetEQ` with `EQType AudioDelay` (0–5, soundbars only). Added the EQ type, surfaced it on `TheaterSettings`, fetch it in `getTheaterSettings`, and added a slider to the Home Theater section of `SpeakerSettingsView`

### Catalyst inspector two-click fix
- Fixed the inspector (Queue) needing two clicks to open on Mac (Catalyst) — the first click was consumed re-syncing presentation state before the toggle registered

### Token refresh hardening
- `TokenRefreshCoordinator` now persists the refreshed token through the handler inside the shared task, before the dedup entry is removed and before any coalesced caller resumes. Previously the entry was removed the instant the network refresh returned, so a caller arriving in the completion-to-persist window re-refreshed with a dead token and invalidated the result; every caller also did its own redundant keychain read-modify-write
- Dedup is keyed on `householdId` instead of the stale `token:key` pair, so callers holding different stale token generations for the same household join one refresh instead of racing each other
- Waiting on the shared refresh is now cancellation-responsive: a cancelled caller (e.g. a dismissed SwiftUI screen) bails out immediately via a continuation bridge while the refresh keeps running for the other waiters (bare `task.value` ignored caller cancellation and could suspend for the full URLSession timeout)
- `SpotifyAPI.authorizedRequest` no longer `try?`-swallows a shared refresh failure into an immediate `invalidToken`, so a genuinely valid session is no longer surfaced to the user as signed-out

### Sonos Radio
- New `MediaSearchService.sonosRadio` / `MusicService.sonosRadio`; registered in browse (`BrowseScreen`), onboarding (`ServicesStep`), and `AppRegistry`
- Reached via SMAPI (no public REST API): `SonosRadioAPI` + `SMAPIEnvelope`/`SMAPICredentials`/`SMAPIMedia`/`SMAPIMediaParser` in `MusicSearchKit`. Endpoint resolved from `ListAvailableServices` (`SonosAPI+SonosRadio`) with a hardcoded fallback
- Auth: SMAPI credentials are the household loginToken (token/key/householdId) plus the controller `deviceId` + `<deviceProvider>Sonos</deviceProvider>`, matching the official controller capture. Service-registry id is **77575** (account UDN/cdudn), distinct from the playback **sid 303**
- Fixed `MediaServerParser` dropping any service with an empty `Nickname0` — Sonos Radio's account has a blank nickname, so its token was being discarded and credentials never resolved
- Search-only per the service PresentationMap (category `station`); browse is presented as curated genre rows, each a station search (`SonosRadioBrowseService` + `SonosRadioBrowseScreen`)
- Playback: `x-sonosapi-radio:<id>?sid=303&flags=32`, `audioBroadcast` class, `SA_RINCON77575` cdudn; ids carry a source prefix (`sonos:`/`tunein:`) whose colon is percent-encoded
- Now-playing: SONOS badge shown on artwork (`ArtworkBadgeView`/`OverlayIcons` via the `Sonos Radio` asset, original rendering); station art used as the artwork fallback during ads — derived from the position-info `albumArtURI` (imgix base before the per-track `mark=` overlay) into `Track.radioStationArtworkURL`
- Fixed constant now-playing/mini-player flicker with an idle (empty-track) Sonos Radio player: each poll stamped station art onto the displayed track (making it non-`.empty`) and then immediately reset it to `.empty` — alternating states every pulse and deleting the widget artwork file each second. Emptiness checks now use `Track.isEmpty` (no trackID and no name — station art doesn't count), and the empty-radio resting track keeps its station branding and is only assigned on change (`SonosService.load` / `updateTrackInformation`)
- Fixed the station artwork URL 503ing after playback: the Sonos Radio `URIMetadata` ran the artwork URL through `ampersandSafe` (`&` → `%26`), corrupting its query separators (`image?w=60%26image=…`); the speaker round-trips that corrupted URL back as `albumArtURI` and every download fails. New `didlEscaped` (`&` → `&amp;amp;`, the same double escape the `<res>` URIs use) preserves the URL through the DIDL round trip. All other `URIMetadata` `albumArtURI` sites (Spotify/Apple/Plex) switched to `didlEscaped` too — behavior-neutral for their current query-less (or single-param) URLs, but the corruption can't recur
- `ArtworkManager`'s failed-download blacklist now expires: a URL that exhausted its 3 retries gets a fresh set of attempts after a 1-hour cooldown (`cleanupFailedURLCache` existed but was never called, so one burst of transient 503s killed that artwork for the whole app session)
- Switching Sonos Radio stations now updates the station art immediately: the fill-in gate in `SonosService.load` only wrote `radioStationArtworkURL` when nil, so while idle the previous station's art stuck around; on a station-title change the new station's metadata art is taken (and cleared if it has none)
- Sharp station artwork: Sonos Radio art arrived as the `sali.sonos.superhi.fi` proxy's `w=60` row thumbnail and was stretched across the player (blurry). New `URL.sonosRadioArtwork(width:)` unwraps the proxy to the inner `sonosradio.imgix.net` URL at w=800 (also sidestepping the proxy's flaky 503s); applied where station art originates — `parseMediaInfo`, the position-info station-base derivation, and SMAPI search results' `artwork` (row `thumbnail` stays w=60). Non-Sonos-Radio URLs pass through untouched. Also repairs the corrupted legacy proxy URLs (`w=60%26image=…`) that pre-`didlEscaped` builds baked into the speaker's queue metadata, so old queues self-heal instead of 503ing until re-queued
- Mini player now shows the station: the marquee falls back to `radioStation` when the track has no song/artist (matching the large player), and `PlayableContent.imageKey` no longer degenerates to `""` for identity-less content (empty trackID + album, e.g. the idle-radio resting track) — it keys off the artwork URL instead, so the station image gets a real Nuke cache identity in the mini player
- Station art no longer requires opening the large player first: the background poll (`updateTrackInformation`) kept the previous track on an empty radio pulse and never wrote station art to the room — only `load()`'s selected-group path did (which runs solely while the large player is open, since it sets `selectedGroup` and its `onDisappear` clears it). Idle radio groups now settle into the same station-branded resting track in both paths
- Fixed the previous station's artwork surviving a station switch (e.g. "DAS BUNKER RADIO" label over Nashville Now art): the background poll updated the station *title* but had no art reset, so when the new station's URIMetadata carried no `albumArtURI`, the resting-track fallback kept the old station's art — and the large player's own reset never fired because by the time it opened the title had already changed. The background poll now mirrors `load()`'s title-change art reset (nil when the new station has no art — a placeholder beats the wrong station's branding)
- Fixed idle radio rooms swapping each other's artwork in the large player (Move 2 showing Theater's station art and vice versa): `ArtworkView.imageIDKey` collapsed to a bare `".player"` for a track with no album/name/trackID, so every idle radio room shared one Nuke cache entry and displayed whichever station's image was cached first. Identity-less tracks now key by their artwork URL — same degenerate-key fix `PlayableContent.imageKey` got for the row/mini-player path

---

## 2026.5

### ClicAction extension ("Listen with Clic")
- New `com.apple.ui-services` Action extension that appears in the Actions row of the share sheet (separate from PlayAction which sits in the Share row)
- Display name: "Listen with Clic"; bundle ID `$(BUNDLE_ID).ClicAction`
- Shares `QueueListView.swift`, `ActionViewController.swift`, and `PlayHistoryService.swift` from the PlayAction folder via `PBXFileSystemSynchronizedRootGroup` + exclusion sets — no file duplication
- Embedded in both Clic iOS and Clic Mac targets

### Share sheet queue position selector
- `QueuePosition` picker added to the content header (hidden for radio content)
- Pre-selects `.replace` for playlists, `.now` for everything else when content loads
- Options: Now / Next / Last / Replace (Front excluded as irrelevant for the share context)
- Both `performPlay` and `playInGroup` now use the `queuePosition` state instead of hardcoded logic

### Share sheet UI refinements
- Room subtitle shows current track name if playing, grouped info ("Grouped with Kitchen +2") if in a multi-room group but nothing playing, or "—" if idle and ungrouped
- Volume button replaced with a capsule `Label("Volume", …)` using small caps so its function is self-evident
- Content header card uses `.glassEffect(.regular.interactive())` on iOS 26; falls back to `.thinMaterial` on earlier OS

### Apple Music artwork quality fixes
- `ITunesLookupItem.artworkURL(size:)` now requests `cc` (crop-center) format instead of `bb` (background letterbox) — eliminates white padding on album/playlist artwork throughout the app
- `AppleMusicOpenGraphAPI` rewrites the landscape `og:image` social-card URL (1200×630) to a square 600×600cc crop from Apple's CDN before storing it in `PlayableContent.artwork` — fixes blurry/cropped artwork in the share sheet for editorial playlists

### Hardware volume buttons (iOS)
- `HardwareVolumeService` intercepts hardware button presses via AVAudioSession KVO on `outputVolume`; translates deltas into `setRelativeGroupVolume` calls on the active Sonos group
- `MPVolumeView` kept in the SwiftUI hierarchy (1×1, alpha 0.0001) to suppress the system volume HUD
- Volume parked at midpoint (0.5) only when near an extreme (≤0.15 or ≥0.85) to avoid unnecessary system volume changes; original volume restored on `stop()`
- Pauses listening when app backgrounds, resumes on foreground via `AsyncStream<AppEvent>`
- Toggle added to Playback section in preferences (`AppStorageKeys.useHardwareVolumeButtons`); modifier applied on the player screen via `.hardwareVolumeControl(group:)`

### Spotify album saving
- Added `saveAlbum`, `deleteAlbum`, `isAlbumSaved` to `SpotifyAPI` (`PUT/DELETE/GET /v1/me/albums`)
- Added `saveSpotifyAlbum`, `deleteSpotifyAlbum`, `isSpotifyAlbumSaved` wrappers to `MusicSearchService`
- `FavoriteMenuButton` now routes `.album`/`.libraryAlbum` content to album endpoints for Spotify; tracks fall through to the existing track endpoints
- Works from search results, album detail page (`MediaDetailView` → `PlayableMenuView`), and anywhere else `FavoriteMenuButton` appears

### Apple Music album favoriting
- Added `updateAlbumFavoriteStatus(albumId:favorite:)` and `isAlbumFavorite(albumId:)` to `AppleMusicAPI`
- Uses `PUT/DELETE /v1/me/ratings/albums/{id}` (same rating system as songs)
- Adds album to library first (`POST /v1/me/library?ids[albums]=`) before rating — required for the rating to persist (same pattern as songs)
- `FavoriteMenuButton` routes `.album`/`.libraryAlbum` for Apple Music to these new methods

### Spotify artist following (removed)
- Explored `PUT/DELETE /v1/me/following?type=artist` — returns 403 Insufficient client scope
- App does not request `user-follow-modify` OAuth scope; would require user re-auth to add
- Feature removed; artist follow button not shown anywhere

### MusicService cross-version decode resilience
- `MusicService` (plain Codable enum, no RawValue) is synthesized as a single-key keyed container (`{"caseName":{}}`). When a case is added in one app version (e.g. `deezer`) and removed in a later one, iCloud-stored play history or queue data containing that case caused a decode failure: `allKeys` returned 0 known keys → "Invalid number of keys found, expected one" → crash via `assertionFailure` in `CloudStorage+Codable.swift`
- Added a custom `init(from:)` to `MusicService` in both `SonosKit` and `SonosKitMini` using a dynamic `CodingKey` struct so any unrecognized case key falls back to `.unknown` instead of throwing
- Synthesized `encode(to:)` is unchanged — existing stored data remains compatible

### QueueManager cleanup
- `addToQueue(item:)` now delegates to `add(items:)` to eliminate duplicated continuation/Task logic
- `add(items:)` yields all items then fires a single `Task { @MainActor in }` for the last non-banner item, down from one Task per item
- `playFolder()` replaced its per-item `addToQueue` loop with a single `add(items:)` call over a mapped array; first playlist gets `.replace`, subsequent ones get `.end`, fixing the folder queue behavior end-to-end
- `QueueManager` marked `@Observable` so `isProcessing` and `lastQueuedItem` are trackable by SwiftUI
- `playSong` marked `@MainActor` (matches its `@MainActor` caller `processQueue`); inner `Task { @MainActor in }` for play history update removed
- `handleError` made `async`; `sonosService.services()` awaited directly instead of inside a nested unstructured `Task`
- Deleted ~50 lines of commented-out dead code

### Last.fm popular tracks + remote feature flags

#### Popular tracks (Plex + library artists)
- `LastFMAPI` added to `MusicSearchKit` — calls `artist.gettoptracks` (limit 50, HTTP-cached via `Cache-Control: max-age=3600`)
- `PopularTracksService` added to the app layer; owns `LastFMAPI`, title normalisation, and two focused methods: `matchLastFM(artistName:songs:)` and `matchAppleMusic(artistName:songs:)`
- Title normalisation strips parentheticals, brackets, dash-suffixed keywords (remaster/live/remix etc.), and bare `feat.`/`featuring`; prefers shorter title when two songs normalise to the same key (avoids returning a remix over the original); prefix-word fallback catches trailing variants not handled by stripping
- `MusicSearchService` no longer knows about Last.fm or flag state; `lookupPlexArtistTopTracks` replaced by `lookupPlexTracks(id:)` — returns raw viewCount-sorted Plex tracks only
- `ArtistDetailView` orchestrates: checks `RemoteFeatureFlags.isEnabled(.lastFM)` before calling Last.fm; library artists fall back to Apple Music `topSongs` when Last.fm is off or returns no matches; Plex artists show no popular tracks section when flag is off
- "Powered by Audioscrobbler" row added to Preferences → About

#### Remote feature flags
- `RemoteFeatureFlags` — `@Observable` singleton, fetches `https://api.clic.dance/flags` on launch; decodes `[String: RemoteFlag]` (fields: `enabled`, `minVersion`); merges into a `Set<Flag>` rather than replacing (omitted flags keep their prior state)
- `minVersion` check uses `.numeric` string comparison so "2.10" > "2.9" is handled correctly
- `DEBUG` builds skip the fetch and default all flags to enabled; `Release` starts with all flags off
- `BetaFeatures.swift` deleted (was dead code — only reference was commented-out Tidal toggle)
- `RemoteFeatureFlags` injected into the environment via `AppRegistry`; consumed in `ArtistDetailView` via `@Environment(RemoteFeatureFlags.self)`
- Cloudflare Worker at `api.clic.dance/flags` — plain JS, no dependencies, single `FLAGS` object to edit and `npx wrangler deploy`

### Start Live Activity shortcut and Control Center widget
- `CreateLiveActivityIntent` renamed from "Create" to "Start Live Activity", made discoverable, given a `description` and `parameterSummary`
- `perform()` now uses `$room.requestValue()` when room is nil (Shortcuts flow without a pre-configured speaker) instead of throwing; room is resolved to `coordinatorID` via `getGroupCoordinatorWithRoom` so grouped speakers are handled correctly
- `AppShortcut` registered in `ClicAppShortcutProvider` with phrases "Start live activity in Clic" and "Start [speaker] live activity in Clic"
- `StartLiveActivityControlWidget` added (iOS 18+) — `AppIntentControlConfiguration` wrapping `CreateLiveActivityIntent`, shows configured speaker name on the button, registered in `WidgetBundle`

### MiniPlayer TV mode controls
- `MiniPlayerView` body restored to the original single `#if !targetEnvironment(macCatalyst) && !os(visionOS)` guard — no tvOS platform splits
- `groupInfoButton` label now contains a `ZStack` that crossfades between the normal layout (track marquee + play/pause + next) and the TV mode layout (audio input format + TV controls) via `opacity` driven by `group.TVMode`
- `artworkView` is itself a `ZStack`: `ContentArtworkView` fades out and a hierarchical `"tv"` SF Symbol fades in when `TVMode` is true — matching the treatment in `TVPlayerView`
- `tvInputInfoView` shows `group.nameWithCount` (caption2) and `group.tvSettings?.audioInputFormat.description` (semibold) in place of the song/artist marquee
- `MiniTVControlsView` (private struct) renders night mode (`moon.zzz.fill`), mute (`speaker[.slash].fill`), and speech enhancement (`person.wave.2.fill`) as `.bordered` buttons; `.controlSize(.small)` on the HStack keeps them the same scale as the existing playback buttons; mute inlined to avoid `MuteButton`'s hardcoded 40×36 frame

### Mac Dock menu reorder
- `DockMenuRenderer.populate` reordered so the least-used controls are at the top and transport is at the bottom (closest to the Dock icon, where the cursor already is)
- New order: Sleep Timer → Playback section header (Repeat / Shuffle / Crossfade inline) → Volume → Speaker switcher → Now Playing + Favorite → Transport
- Repeat / Shuffle / Crossfade previously had no section label; now preceded by a disabled "Playback" header instead of a submenu
- Favorite moved from its own separator-bounded section into the Now Playing group, directly below the track line

### Spotify same-album artwork flicker fix
- Root cause: three compounding issues caused artwork to flash when skipping between Spotify tracks on the same album
- **Double URL churn** — `SonosService` assigns the new `Track` from Sonos XML immediately (before the CDN URL arrives), resetting `downloadedArtworkURL` to nil. This caused `ArtworkView`'s `.task(id: artworkURL)` to fire twice: once for the Sonos proxy URL and once for the Spotify CDN URL. The Sonos proxy is unreliable at track boundaries, so the first fire often fails → grey placeholder flash
- **Unstable Nuke cache key** — `imageIDKey` in `ArtworkView` was keyed on `album + artist`. Sonos sends `dc:creator` (per-track artist) for Spotify, not `r:albumArtist`. On featured tracks the artist string varies between songs, so the cache lookup missed even though the album art is identical
- **Error handler blanked artwork** — `ArtworkView` nil'd `currentImage` on any failed image load, guaranteeing a visible blank frame on Sonos proxy failures
- **Fix 1 (SonosService, two sites):** when `awaitedTrack.album == currentTrack.album` and `!awaitedTrack.album.isEmpty` and a prior `downloadedArtworkURL` exists, carry that URL into `awaitedTrack` before the early assignment. `artworkURL` never changes during a same-album skip, so `.task` never refires at all. The CDN URL from `getTrackInformation` still overwrites when it arrives, but it's a no-op (same URL for same album)
- **Fix 2 (ArtworkView.imageIDKey):** simplified to `album.service.player` for all services — Spotify same-album tracks share one cache entry regardless of featured-artist variation in `dc:creator`; including `service` prevents cross-service collisions (e.g. a Plex album with the same name as a Spotify album)
- **Fix 3 (ArtworkView error handler):** swallow load errors silently instead of nil-ing `currentImage`; the `guard let artworkRequest else { currentImage = nil }` path still clears artwork when the track genuinely has no URL

### Unified queue context menu
- `UpNextContentView` and `QueueScreen` (full queue) now share a single `.contextMenu(forSelectionType: String.self)` path; the single-selection branch (`trackIDs.count == 1`) builds the full action set — `AddToPlaylistMenu`, View Album, View Artist, and Play Next — while multi-selection keeps `AddTracksToPlaylistMenu` + bulk Remove
- Removed the `#if targetEnvironment(macCatalyst)` per-row `.contextMenu { menu(content:) }` from `fullQueueView` and deleted the now-unused `menu(content:)` builder — Catalyst right-click now flows through the same selection-based menu instead of a parallel per-row one
- Both views were previously inconsistent: Up Next only offered Add to Playlist + Remove, while the full queue had a richer Mac-only per-row menu. Single code path means feature parity across Up Next / Full Queue and iOS / Mac

### Music service menu icon hit target (iOS 26)
- The music service selector `Menu` labels in `MediaSelector.swift` and `SearchScreen.swift` had an offset/undersized tap area on iOS 26
- Wrapped each label in an `.iconOnly` `Label` to restore the standard toolbar hit target
- `.iconOnly` re-tints the icon with the control color, so re-applied `.foregroundStyle(brandColor.gradient)` on the `Label` to restore the per-service brand color
- Kept `.frame(width: 24, height: 24)` on the icon image so sizing stays correct

### Search & library results grid layout
- New `PlayableContentGridView` — a two-column `LazyVGrid` that renders the extracted `PlayableContentRowView` per item (`.geometryGroup()` per cell)
- Used by search results and `AppleLibraryBrowseScreen` in place of the prior single-column list
- `SpotifySearchScreenUpdated` consolidated back to `SpotifySearchScreen` (preview + `SearchEmptyStateView` references updated)
- `RecentSearchesView` titles now leading-aligned and full-width (`maxWidth: .infinity`) instead of a fixed 70pt frame; tighter `VStack` spacing

### Average color extraction performance
- `UIImage.findAverageColor` now uses integer multiply (`r * r`) instead of `pow()` in the `.squareRoot` path — exact and far cheaper per pixel
- Pixel loop iterates rows contiguously (`y` outer, `x` inner) for better CPU cache locality
- Cache reads/writes go through `NSLock.withLock`, collapsing the lock/unlock boilerplate

### SoundCloud library screen parity with Spotify
- `SoundCloudBrowseScreen` rewritten from a `ScrollView` of horizontal carousels to a `List` of reorderable sections, matching `SpotifyLibraryScreen` and `AppleLibraryBrowseScreen`
- Liked Songs and Playlists now render as two-column `LazyVGrid`s of `PlayableContentRowView` (7 tracks + Play All, 8 playlists) with `NavigationLink` headers into the full lists
- Added `SoundCloudLibrarySection` enum, a `soundcloudLibrary` `SectionConfigurationStore`, and `ReorderSoundCloudLibrarySectionsView` so sections can be reordered/hidden via the toolbar filter button
- New `.reorderSoundCloudLibrarySections` sheet destination wired through `SheetDestination` and `AppRegistry`
- Auth-error and empty states preserved as List fallbacks; loading stays cursor-based (`updateLikedTracks`/`loadMoreTracks`) since SoundCloud has no offset/limit API

---
