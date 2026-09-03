# Guest Queue

Let guests add songs to your Sonos queue without needing to know which room to pick. Host generates a QR code or shareable link; guest scans it and lands directly in that group's search. SUPER subscription feature.

## Constraint

All Sonos control is local SOAP — there is no cloud relay. This means guests must be on the same WiFi as the Sonos system and must have Cue installed. A true "anyone on the internet adds to queue" feature would require building a backend server.

## UI: GuestQueueSheet

Sheet destination: `.guestQueue(group: GroupRoom)`

Contents:
1. Hero: "Let guests add to [Group Name]"
2. QR code — rendered via `CIQRCodeGenerator` (no third-party lib) encoding `cue://group?id=<coordinatorID>`
3. `ShareLink` button for the URL (AirDrop, iMessage, etc.)
4. "Copy link" button
5. Disclaimer: "Guests need Cue and must be on the same Wi-Fi as your Sonos system."

If not subscribed: QR area replaced with `PaywallButtonView` + locked overlay.

Entry point: "Guest Queue" item in the queue screen's more-info menu (`QueueScreen`).

## Deep Link Handler

Add `cue://group?id=<id>` to `CueApp.handle()`. Selects the group and opens the search sheet for it. (`cue://device?id=` already follows this same pattern in `CueApp.swift`.)

## Files

| Action | File |
|--------|------|
| Create | `Cue/Queue/GuestQueueSheet.swift` |
| Modify | `Cue/Routing/SheetDestination.swift` — add `.guestQueue(group: GroupRoom)` |
| Modify | `Cue/Routing/AppRegistry.swift` — register in `withSheetDestinations()` |
| Modify | `Cue/Queue/QueueScreen.swift` — add menu item |
| Modify | `Cue/CueApp.swift` — add `cue://group?id=` handler |
