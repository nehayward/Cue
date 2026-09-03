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

    private init() {}

    func requestFocus() {
        requestCount += 1
    }
}
