# Port from Clic: services signing out and not loading

On 2026-10-03 Clic fixed services that stopped loading (SoundCloud, Deezer, Pandora, Sonos Radio, Spotify sections) until the app was force quit. Cue has the same code in `SonosKit` and `MusicSearchKit`, so it has the same bugs. This note lists the Clic commits to bring over.

**Status: ported** on Cue branch `claude/service-sign-in-fixes`. Build-tested for iOS, Mac and watch; not yet run against speakers.

**Where:** Clic branch `claude/stale-service-tokens` (nehayward/Clic), pushed and unmerged. Tested on the simulator against the real speakers; not yet on a phone.

**How to bring a commit over:** `git -C <Clic> format-patch -1 <sha>`, then `git am -3` here. Expect small conflicts where Cue differs:
- `KeychainTokenRefreshHandler.swift`: Cue's app group is `group.dance.cue` (Clic: `group.com.clic`). Keep Cue's.
- `MediaServerHandler.swift`: Cue only borrows the household's Plex token when it has none of its own. Keep that block.
- Cue has no `SMAPIServiceClient` or SiriusXM. Its Pandora refresh is in `PandoraAPI.swift`, which has the same code as Clic's `SMAPIServiceClient`.

## 1. Must port: services signed out until relaunch

- `e1c640ae` **Never save an empty household id.** `onServerListening` re-reads the household id from a speaker on every activation. `getHouseHoldID` returns `""` when that read fails (common right after resuming), and saving it made every keychain-backed service (SoundCloud, Deezer, Pandora, Sonos Radio) look signed out until relaunch. Cue's `SonosService.onServerListening` has exactly this code. The commit also makes a failed SMAPI token refresh go back to the stored token instead of pinning the dead one: apply that part to Cue's `PandoraAPI.swift` and `SonosRadioAPI.swift` (`if let refreshed { state.refreshedLogin = refreshed }` → `state.refreshedLogin = refreshed`).
- `3b6c2c23` **Use the speakers' latest tokens without a relaunch.** Credentials were cached the first time they were read and never dropped when the speakers sent new ones. Adds `invalidateCredentials(for:)` to `TokenRefreshHandler` and a retry on SoundCloud 401.

## 2. Must port: switching services mid-load broke them

Switching Browse services cancels the old screen's `.task`, and its cancelled requests come back empty. Several services stored that as the real answer.
- `76679681` Sonos Radio (`hasLoaded` stuck → "Couldn't load" until relaunch), Pandora (until stale), SoundCloud (false "not authenticated").
- `fcbf0700` Deezer and Subsonic blanked their lists; Spotify hid suggestion sections and kept failed seed artists.

## 3. Worth porting: cleanup of the same code

- `1ebca973` `KeychainTokenRefreshHandler` keeps each household's accounts in memory behind an unfair lock (was a per-service cache on a concurrent queue whose async-barrier clear could race a read). One `server(for:in:)` picks the account (the three copies disagreed when the chosen primary account was gone). `getCredentials(for: String)` maps the name instead of always returning SoundCloud. `SonosAPI` remembers each speaker's household id for 10 minutes. Pandora/SiriusXM and Sonos Radio share `SMAPILoginSession` for token refresh. In Cue, point `PandoraAPI` and `SonosRadioAPI` at `SMAPILoginSession`.

## Clic only (skip)

- `76db9887`, `c21c2cd2`: SiriusXM loading speed. Cue has no SiriusXM.
