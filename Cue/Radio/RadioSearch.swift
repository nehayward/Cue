import Foundation
import Observation
import SonosKit

/// The Radio tab's search: one query, asked of each station source that is
/// switched on, answered as a section per source. Debounced here, so the
/// screen's `.task(id:)` only has to restart it on each keystroke.
@MainActor
@Observable
final class RadioSearch {
    private(set) var tuneIn: [PlayableContent] = []
    private(set) var apple: [PlayableContent] = []
    private(set) var isSearching = false

    var isEmpty: Bool {
        tuneIn.isEmpty && apple.isEmpty
    }

    func clear() {
        tuneIn = []
        apple = []
    }

    /// Runs `query` against the enabled sources. Cancelling the task —
    /// which the next keystroke does — drops the answer.
    func run(
        _ query: String,
        tuneIn searchTuneIn: Bool,
        apple searchApple: Bool,
        using musicSearchService: MusicSearchService
    ) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clear()
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        async let tuneInResults = Self.tuneInStations(query, enabled: searchTuneIn, musicSearchService)
        async let appleResults = Self.appleStations(query, enabled: searchApple, musicSearchService)
        let (found, foundApple) = await (tuneInResults, appleResults)

        guard !Task.isCancelled else { return }
        tuneIn = found
        apple = foundApple
    }

    private static func tuneInStations(_ query: String, enabled: Bool, _ service: MusicSearchService) async -> [PlayableContent] {
        guard enabled else { return [] }
        return await service.searchTuneInStations(query: query)
    }

    private static func appleStations(_ query: String, enabled: Bool, _ service: MusicSearchService) async -> [PlayableContent] {
        guard enabled else { return [] }
        return await service.searchAppleRadioStations(query: query)
    }
}
