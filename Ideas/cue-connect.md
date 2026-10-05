# Cue Connect

Cue on one device shows and controls Cue playing on another, and hands the queue across, the way Spotify Connect does. The Mac is playing; the iPhone's mini player says "Playing on MacBook" with a live progress bar, its controls drive the Mac, and the Mac is a row in Play On. Not built yet: Cue instances don't talk to each other at all today (no Handoff, no Cue-to-Cue networking, no CloudKit container).

## How the others do it

- **Spotify Connect is cloud-first.** Every signed-in device keeps a WebSocket to Spotify's servers and publishes its state there. The phone reads the "cluster" of devices and sends commands through it. Local mDNS (`_spotify-connect._tcp`) is only used to log a speaker in the first time. That's why it works across networks, and it's the one part Cue can't copy without running a server.
- **The state model is the part to copy.**
  - The playing device is the authority. It publishes `timestamp` + `position_as_of_timestamp`, play state, duration, queue and volume, and only when they change.
  - Controllers work out the position themselves. That is Cue's running clock (`Docs/PlaybackProgress.md`): no progress ticks over the wire.
  - A transfer is one command carrying the track, position, play state and queue.
  - A state older than the command that made a device active is dropped. librespot hit this bug: a stale update briefly named the old device as active again.
- **Plexamp is a hybrid.** plex.tv lists the players and relays their status; a direct connection carries control.
- **Apple has nothing to borrow.** Control Center's other-speakers list and its Apple TV remote use private protocols (MediaRemote, Companion Link), so no third-party app can appear there. Music doesn't hand off between iPhone and Mac either.

## Options on Apple platforms

| Option | Verdict |
|---|---|
| Network framework `NetworkListener` / `NetworkBrowser` / `NetworkConnection` over Bonjour (iOS and macOS 26) | **The core.** Milliseconds, no server. Cue's iPhone and Mac targets already deploy at 26. Needs the same Wi‑Fi, or Apple's peer-to-peer Wi‑Fi with `.peerToPeerIncluded`. Costs a Local Network prompt. |
| Handoff (`NSUserActivity`) | **Cheap first win.** "Continue on Mac" from the Dock, with no prompt and no server. Not live control. |
| Own relay: a Durable Object on the Cloudflare Worker that serves cue.dance | **Later**, for control away from home. Free tier to $5 a month. |
| CloudKit subscriptions, iCloud KVS | **Presence only.** Silent pushes are coalesced, throttled to a few an hour, and unreliable on macOS (a minute late or never). KVS updates a few times a minute. Fine for "which Cue devices exist", useless for a pause button. |
| Multipeer Connectivity | **No.** Deprecated as of Xcode 27 (TN3213), and it stops when the app goes to the background. |
| Wi‑Fi Aware, DeviceDiscoveryUI | **No.** Neither exists on macOS. DeviceDiscoveryUI might suit an Apple TV later. |
| AirPlay to Mac | Already in the picker when Sonos is off. The phone stays the source and Cue on the Mac knows nothing, so it isn't Connect. |

## Recommendation

One protocol, three steps:

1. **Handoff.** Small, and ships alone.
2. **Local Connect** over Network framework: live state, control, transfer. This is the feature.
3. **Relay**, later. It carries the same encrypted messages when the devices aren't on the same network.

Before step 2, build the `PlaybackController` protocol (`Ideas/sonos-separation.md`, Phase 2). Today every player view branches on `route.group` (`CueApp.swift:44`, `PlayerView.swift`, `QueueNextUpView.swift`). A remote Cue would add a third branch to all of them. With the protocol it is a third implementation instead, `RemoteCuePlayer`.

## Design

### Roles

- **Player**: a Cue that plays on itself: iPhone, iPad, or the Mac (Catalyst, same `LocalPlaybackService`). It advertises while Connect is on and Cue is running, and it is the authority over its own state.
- **Controller**: a Cue showing another device's playback. Every player is also a controller.
- **A Mac playing to a Sonos group** publishes "Playing on Living Room" and nothing more. The iPhone controls that group itself if Sonos is on; Connect never relays Sonos.
- **Apple TV and the watch** come later, as controllers only. The TV has no local player yet. The watch can't use Bonjour or sockets outside audio streaming (TN3135), so it would go through the iPhone over WatchConnectivity, which `Ideas/device-player-roadmap.md` already plans for controlling the phone.

### Messages: `Packages/CueConnect`

Pure Foundation and CryptoKit, tested with `swift test`, like `WatchSync`.

- **`Hello`** `{ deviceID, name, kind, protocolVersion, capabilities }`, followed by a ping/pong that estimates the clock offset between the two devices (NTP-style, four timestamps).
- **`PlayerState`** `{ revision, nowPlaying: PlayableContent?, upNext, positionAnchor, anchoredAt, isPlaying, duration, volume, repeatMode, isShuffled, route }`, sent only on change.
  - `upNext` is the first 100 items plus the total count.
  - The offset converts `anchoredAt` to the controller's clock. From there it is `progressAnchor` / `progressAnchoredAt`, kept exactly as `LocalPlaybackService` keeps them (`:179-181`) and drawn through `PlaybackTimeline`.
- **`Command`** `{ id, action }`: play, pause, next, previous, `seek(to:)`, `setVolume`, `jump(index)`, `enqueue(items, at:)`, `remove`, `move`, `setShuffle`, `setRepeat`.
  - Each maps 1:1 to a `LocalPlaybackService` method.
  - Each is answered by `Ack { id, revision }`.
  - A controller ignores any state with a revision older than its last acked command's. That is the stale-state rule from Spotify.
- **`Transfer`** `{ snapshot }` and **`TransferRequest`** carry hand-offs.
  - The snapshot is `PlaybackRoute`'s private `Snapshot` (`:263`), made Codable.
  - It gains shuffle and repeat, which it doesn't carry today. Sonos hand-off gets them too.

### Transport and security

- **Listening and browsing.** Each player runs a `NetworkListener` advertising `_cue._tcp`, and controllers browse with `NetworkBrowser`. The framework's built-in TLV framing carries sealed envelopes. Browse only while the Play On menu is open or Cue is idle in the foreground, and keep one connection open to the device being controlled.
- **Who may connect.** Bonjour shows the control port to everyone on the network, so every connection has to prove it belongs to the same person.
  - The proof is a random 256-bit secret in **iCloud Keychain** (`kSecAttrSynchronizable`), created by whichever device turns Connect on first.
  - The iPhone and Mac apps share the app id `TEAMID.dance.cue`, so they should share the default access group. Check this on a device.
- **Handshake.**
  - Both sides send a random nonce, and the session keys are HKDF-SHA256 over the secret and both nonces.
  - Every message is sealed with ChaCha20-Poly1305 and a counter.
  - This needs CryptoKit only, no new dependency. The same envelope later runs over the relay, so the server only ever sees ciphertext.
- **Not TLS.**
  - Not TLS-PSK: TN3213 says it is TLS 1.2 only and works only with the old `NWConnection` API.
  - Not mutual TLS either: it needs self-made certificates (swift-certificates) and does nothing for the relay.
- **TXT record.** It carries an opaque, rotating id, not the device's name. The name comes after the handshake.
- **No iCloud Keychain, no Connect in v1.** Say so in Settings. A pairing code is the later fallback, but a short code used as the key can be brute-forced offline (Apple's TicTacToe sample, FB13589481), so it would need a PAKE.

### Where it plugs in

- **`PlayDestination`** gains `.cue(deviceID)`, stored as `cue:<id>`.
  - `remembered` (`Packages/Defaults/.../PlayDestination.swift:24`) reads any string that isn't `device` as a Sonos coordinator, so decode the prefix first.
  - Every exhaustive switch on it grows a case: `PlaybackRoute.switchTo`, `PlayDestinationRouter.play`, `PlayAction/QueueListView.swift`.
- **Hand-off to the Mac** (`handOffToCue`) is the same overlapped start `handOffToGroup` already does for speakers (`PlaybackRoute.swift:325`):
  1. Send `Transfer` with the position moved ahead by a startup estimate.
  2. Wait for the Mac's `Ack` that it is playing.
  3. Call `LocalPlaybackService.park()`.

  The Mac resolves items the way `handOffToDevice` does (`localItem`, `:703`):
  - Apple Music by catalog id, under the Mac's own subscription.
  - Plex and Subsonic by id, with the Mac's own sign-in. Don't use the sender's `previewURL`: it carries the sender's token.
  - Files stay behind (`playsOnDeviceOnly`), as with Sonos.

  Items the Mac can't play are reported, not silently dropped: "3 songs need Plex on MacBook".
- **Hand-off back to the iPhone** is pulled from the iPhone ("Play here"). The iPhone sends `TransferRequest`; the Mac answers with its snapshot and keeps playing until the iPhone acks, then parks. The Mac can't push playback onto a suspended iPhone, because iOS won't start a non-mixable audio session from the background.
- **Play On menu.**
  - A "Cue Devices" section goes in `SonosRouteMenu` between This Device and Speakers (`PlaybackRouteButton.swift:55`).
  - With Sonos off, `PlaybackRouteButton` is the bare AirPlay picker today (`:28`). It becomes a menu (This Device, Cue Devices, AirPlay) only once another Cue device is known, so nothing changes for someone with one device.
  - `RouteTransferPrompt` gets device names and symbols (`laptopcomputer`, `iphone`, `ipad`).
- **Lock Screen and volume buttons on the iPhone.** `NowPlayingSessionService` and `SilentAudioSession` already put a Sonos group on the system card, and hold the audio session that keeps Cue running in the background. A remote Cue uses the same mirror, which also keeps the connection to the Mac alive while the phone is locked.
- **Seeing the Mac without switching to it.** When this device is idle and another Cue is playing, the mini player shows the remote state with a Control button, as Spotify does. This is the "show its progress whether or not it's the chosen destination" part. Control switches the route without moving anything.

### Presence and the Local Network prompt

- **The constraint.** With Sonos off, Cue never shows the Local Network prompt today (CLAUDE.md, Sonos Integration). Bonjour browsing and advertising both need it, on iOS and on macOS 15 and later.
- **iCloud registry first.** Each device writes itself to a small registry in iCloud KVS at launch (`CloudKeys.cueDevices`: id → name, kind, last seen). Nothing touches the network until the registry shows a second device that can play.
- **Prompt on a tap.** Play On then shows that device with "Find on This Network", and the prompt comes from that tap. This is the same opt-in pattern as `SonosQuestionStep`.
- **Device states.** The registry gives the device list its states: **Playing** and **Available** when found on the network, **Not nearby** when known from iCloud but not found. That covers "whether or not the Mac is connected".
- **Info.plist.** `_cue._tcp` goes in `NSBonjourServices` in `Cue/Info.plist` and `Mac/Cue-Mac.plist`, and `NSLocalNetworkUsageDescription` stops mentioning only Sonos.
- **What KVS holds.** KVS isn't encrypted, so it holds names and kinds only: never the secret, never a queue.

### Handoff (step 1)

- **Publishing.** While Cue plays and is frontmost, it publishes an `NSUserActivity` of type `dance.cue.playback` (listed in `NSUserActivityTypes`).
  - It holds the current item's service, type and id, the position with the time it was captured, and up to about 20 upcoming ids.
  - `userInfo` must stay under about 3 KB.
  - The Mac shows Cue in its Dock with the iPhone badge.
- **Continuing.** The receiving device resolves the items as `handOffToDevice` does and starts at the position plus the time elapsed since capture.
- **Stopping the source.** The source gets `userActivityWasContinued(_:)` and parks itself, so the phone stops when the Mac starts without any connection between them. The full queue can follow over `supportsContinuationStreams`.
- **Limit.** Handoff only advertises the frontmost app. It covers "I was in Cue on the phone, then sat down at the Mac", not playback started from the Lock Screen. That is what Local Connect is for.

### Platform notes

- **Mac.**
  - The Catalyst app must be running to appear, so it advertises only while it runs. App Nap doesn't apply while it plays; check that the listener still answers when Cue is idle and hidden, and after sleep.
  - The Mac target sets `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO` while `Cue/Cue.entitlements` grants `network.server`. Check the signed app (`codesign -d --entitlements - Cue.app`) before relying on the listener.
  - Cue Mini (a separate AppKit process, Sonos only) is out of v1. Later it could browse `_cue._tcp` on the same Mac to show device playback (roadmap Tier 3).
- **Device names.** On iOS 16 and later, `UIDevice.current.name` is just "iPhone" without the user-assigned device name entitlement (`com.apple.developer.device-information.user-assigned-device-name`). Request it, since showing the user's own devices in a picker is the kind of use it's granted for, and fall back to a name typed in Settings. Check what Catalyst returns on the Mac.
- **iPad** works like the iPhone.
- **tvOS**, later, as a controller only. It needs the old `NW*` API at its tvOS 18 target. tvOS doesn't sync iCloud Keychain, so the secret would come from a CloudKit record's `encryptedValues` or from pairing.

## Branches

0. **`claude/playback-controller`.** `Ideas/sonos-separation.md`, Phase 2. A prerequisite for branch 3.
1. **`claude/playback-handoff`.** Publish and continue `NSUserActivity`; the source parks when continued.
   Done when: Cue playing on the phone shows in the Mac's Dock, clicking it starts the same song within a second of where the phone was, and the phone stops.
2. **`claude/cue-connect-kit`.** `Packages/CueConnect`: messages, envelope, handshake, clock offset, stale-state rule, tests.
3. **`claude/cue-connect-remote`.** Listener and browser, KVS registry, Keychain secret, a Settings switch, and `RemoteCuePlayer` on the controller protocol.
   Done when:
   - the Mac plays and the iPhone's mini player and full player show it within a second;
   - the bar matches the Mac's to within half a second;
   - play/pause, skip, seek and volume work;
   - the Lock Screen card drives the Mac.
4. **`claude/cue-connect-route`.** `PlayDestination.cue`, the Play On rows, transfer both ways, and viewing and editing the remote queue.
   Done when: phone → Mac and Mac → phone carry the queue, position, shuffle and repeat with no gap, and a failure reverts the way a failed Sonos hand-off does.
5. **`claude/cue-connect-relay`** (later). A Durable Object room keyed by HKDF of the secret, carrying the same envelope. Devices connect while Cue is in the foreground or playing, which also gives presence beyond the local network.

## Open questions

- Free or Cue Super? Remote control and hand-off could be split between them.
- Should the mini player show another device's playback unprompted, or only once that device is picked?
- Is control away from home wanted soon enough to plan the relay now?
- Should Connect also carry Plex and Subsonic sign-ins, the way `WatchCredentials` does, so the Mac can play what the phone queued without signing in itself?

## References

- [TN3213: Moving from Multipeer Connectivity to Network framework](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework)
- [Use structured concurrency with Network framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/250/)
- [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
- [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app), [CloudKit pushes late on macOS (forum)](https://developer.apple.com/forums/thread/816350)
- [kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable)
- [Adopting Handoff](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/Handoff/AdoptingHandoff/AdoptingHandoff.html)
- [go-librespot connect-state model](https://pkg.go.dev/github.com/devgianlu/go-librespot/proto/spotify/connectstate), [stale cluster fix](https://github.com/devgianlu/go-librespot/pull/418)
- [Spotify Web API: transfer playback](https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback)
- [Plex: what goes via the cloud vs. a direct connection](https://forums.plex.tv/t/cannot-cast-to-plexamp-headless-to-control-remotely/853520)
- [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [WebSocket hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
