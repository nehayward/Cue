# Listening Stats

Wrapped-style play history insights gated behind the SUPER subscription. Shows top artists, most-used services, content type breakdown, and monthly track count. Users can share a stats card image.

## The Problem

`PlayHistoryService` stores an `OrderedSet<PlayableContent>` with no timestamps — just insertion order. Stats require a timestamped log of every play event.

## Data Model

Stored in the **User Data SwiftData store** (CloudKit-synced, so stats are consistent across all the user's devices):

```swift
@Model class PlayHistoryEntry {
    @Attribute(.unique) var id: UUID
    var playableData: Data       // JSON-encoded PlayableContent
    var playedAt: Date
    var serviceRaw: String       // denormalized for fast groupBy queries
    var artistName: String?      // denormalized for fast groupBy queries
    var contentTypeRaw: String
}
```

Entries older than 365 days are trimmed on each write. Requires [SwiftData Foundation](swiftdata-foundation.md).

## Stats Service

`ListeningStatsService` — `@Observable final class`, `static let shared`.

Computed from the log via `Dictionary` groupBy (no heavy processing):

- `topArtists: [(String, Int)]` — by `artistName`
- `topServices: [(MusicService, Int)]` — by `serviceRaw`
- `topContentTypes: [(ContentType, Int)]` — by `contentTypeRaw`
- `totalTracksThisMonth: Int`
- `mostActiveDayOfWeek: String`
- Play count per track — group by `PlayableContent.id`, count occurrences

## Wiring

In `QueueManager.playSong()`, after the existing `PlayHistoryService` insert:

```swift
ListeningStatsService.shared.log(content: playableContent)
```

## UI

**`ListeningStatsScreen`** — full screen pushed via `RouterDestination.listeningStats`:
- Monthly headline ("142 songs this month")
- Top Artists (top 5 with play counts)
- By Service — Swift Charts bar or donut
- By Content Type
- Most Active Day

If not subscribed: `PaywallButtonView` at top, stats rows redacted with `.paywall(false)`.

Entry point: toolbar button in `PlayHistoryFullView`.

## Shareable Stats Card

Use `ImageRenderer` (iOS 16+) to render a Wrapped-style card view to PNG on device. User taps "Share My Stats" → standard share sheet → Instagram, iMessage, etc. No backend or URL needed — pure on-device image generation.

## Files

| Action | File |
|--------|------|
| Create | `Cue/Data/PlayHistoryEntry.swift` |
| Create | `Cue/ListeningStats/ListeningStatsService.swift` |
| Create | `Cue/ListeningStats/ListeningStatsScreen.swift` |
| Create | `Cue/ListeningStats/StatsShareCard.swift` — `ImageRenderer` card view |
| Modify | `Cue/Services/QueueManager.swift` — add log call in `playSong()` |
| Modify | `Cue/Routing/RouterDestination.swift` — add `.listeningStats` case |
| Modify | `Cue/Routing/AppRegistry.swift` — register screen |
| Modify | `Cue/Search/PlayHistoryFullView.swift` — add toolbar entry point |
