import Observation

/// Carries "focus the search field" from the tab bar down into `SearchScreen`.
///
/// The field's focus lives in `SearchScreen`'s `@FocusState`, which nothing
/// outside that view can write to, and the tab bar sits above it in `CueApp`.
/// A counter rather than a `Bool`: two consecutive requests have to be
/// distinguishable, or re-tapping the tab a second time would set an already-
/// `true` flag and change nothing.
@MainActor
@Observable
final class SearchActivator {
    static let shared = SearchActivator()

    private(set) var requestCount = 0
    /// A request no screen has taken yet. The Search quick action asks before
    /// the Search tab is showing (on a cold launch, before it exists), so
    /// the counter changes while no `SearchScreen` is there to see it; the
    /// screen takes this as it appears.
    private(set) var isPending = false

    private init() {}

    func requestFocus() {
        requestCount += 1
        isPending = true
    }

    /// Takes the waiting request, so only one screen acts on it.
    func takePendingRequest() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
