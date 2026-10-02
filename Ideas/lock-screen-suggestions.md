# Lock Screen Suggestions

Put what was played in Cue into the row of artwork the Lock Screen shows above Now Playing (and in Control Center and Siri Suggestions), the way Apple Music and Audible already appear there. Not built yet: Cue has no Intents code, no Siri entitlement and no `INIntentsSupported`.

## How the system fills that row

The tiles come from **`INPlayMediaIntent` donations** (SiriKit Media). An app tells the system "the user just played this"; iOS ranks the donations from every app and shows a few. Tapping one sends the same intent back to the app, which plays it. `INUpcomingMediaManager` can add things not yet heard. There is no App Intents replacement for this: it is still SiriKit.

## What it takes

1. **Declare and handle the intent.** The system won't show a tile it can't hand back.
   - Siri capability in `Cue/Cue-iOS.entitlements` (the iOS-only file; `Cue.entitlements` is shared with Mac, TV and Vision).
   - `INIntentsSupported: [INPlayMediaIntent]` in `Cue/Info.plist`.
   - `AppDelegate.application(_:handlerFor:)` returns an `INPlayMediaIntentHandling` handler: the `INMediaItem.identifier` back to a `PlayableContent`, `.handleInApp` so iOS launches Cue in the background with audio allowed, then play.
   - Declaring the intent also opts Cue into Siri voice requests ("play Houdini in Cue"). Those arrive with a `mediaSearch` and no identifier: resolve them, or decline cleanly.
2. **Donate on every play.** `INInteraction(intent: INPlayMediaIntent(mediaItems: [item], …), response: INPlayMediaIntentResponse(code: .success, userActivity: nil)).donate()`, with an `INMediaItem` carrying identifier, title, artist, type (`.song`, `.album`, `.playlist`, `.radioStation`) and artwork.
3. **Later, optional:** `INUpcomingMediaManager.shared.setSuggestedMediaIntents(_:)` for what hasn't been heard yet (new Plex and Subsonic additions).

## Where the donation goes

Recently Played is written in about ten places, each a copy of `history.remove` + `history.insert(at: 0)`:

- `Cue/Services/PlayDestinationRouter.swift` (`record(_:)`)
- `Cue/Services/QueueManager.swift`
- `CarPlay/CarPlayPlayback.swift`
- `Cue/Search/PlayableMenuView.swift`, `Cue/Search/ArtistDetailView.swift`, `Cue/URLPlayMediaView.swift`, `Cue/PlayerSelectionView.swift`
- `PlayAction/QueueListView.swift` (the share extension)

Fold them into one `PlayHistoryService.record(_:)` that also donates. Don't donate by observing `history`: it's `@CloudStorage`, so plays synced from the Mac or iPad would be donated as this phone's.

## Decisions

- **Only donate what the device can play** — `LocalPlaybackService.canPlayAnywhereLocally`, the filter CarPlay's Recents uses. A tap on the Lock Screen must work with no speaker around (Product Priority 3).
- **A tap plays on the current `PlaybackRoute`, falling back to the device.** There is no UI on the Lock Screen, so it must never end in the speaker picker; with Sonos off it always plays on the device.
- **Identifier: the content id, looked up in the synced history.** Not the encoded `PlayableContent`: Plex artwork URLs carry the account token, which shouldn't sit in the system's suggestion store. Same reason artwork goes as `INImage(imageData:)` from `ImageCacheService`, not a URL.

## Testing

iOS decides which apps' plays make the row; tiles usually appear after a few days of use. To see donations at once: Settings ▸ Developer ▸ **Display Recent Shortcuts** and **Display Donations on Lock Screen**.

## References

- [Donate intents and expand your app's presence — WWDC21](https://developer.apple.com/videos/play/wwdc2021/10231/)
- [INUpcomingMediaManager](https://developer.apple.com/documentation/intents/inupcomingmediamanager)
