import SonosKit

extension Sequence where Element == PlayableContent {
    /// Pairs each track with a reorder-stable, unique row key for `ForEach`/list selection.
    ///
    /// A queue can hold the same song more than once, so `content.id` alone isn't unique.
    /// Appending the queue position (as `trackID` does) makes it unique but changes on every
    /// shuffle/move/delete, which defeats SwiftUI's move animations — every row reads as a
    /// brand-new identity, so the list cross-fades instead of sliding.
    ///
    /// Instead we key by content id + the *occurrence index* of that song within the loaded
    /// window ("the Nth copy"). That's unique, and stable under reorder because the multiset of
    /// keys is invariant: a pure shuffle keeps the same keys, so SwiftUI animates rows moving.
    /// The index is relative to the loaded window (the queue is paginated and only ever holds a
    /// slice in memory), which is sufficient — identity only has to be unique and stable within
    /// the array SwiftUI is currently diffing. Duplicate rows are visually identical, so it never
    /// matters which physical copy maps to which key.
    func keyedByOccurrence() -> [(key: String, track: PlayableContent)] {
        var counts: [String: Int] = [:]
        return map { track in
            let occurrence = counts[track.id, default: 0]
            counts[track.id] = occurrence + 1
            return ("\(track.id)#\(occurrence)", track)
        }
    }

    /// Resolves the tracks for a set of occurrence keys (e.g. a list selection).
    func tracks(forKeys keys: Set<String>) -> [PlayableContent] {
        keyedByOccurrence().compactMap { keys.contains($0.key) ? $0.track : nil }
    }

    /// The occurrence key of the row at the given 1-based queue position, if it's loaded.
    /// Used as a scroll target, since `ScrollViewReader` matches the `ForEach` identity.
    func occurrenceKey(forPosition position: Int) -> String? {
        keyedByOccurrence().first { $0.track.metadata?.position == position }?.key
    }
}
