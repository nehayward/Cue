import Foundation
import MusicSearchKit

/// Backs `SonosRadioBrowseScreen`. Sonos Radio's SMAPI service is search-only
/// (its PresentationMap defines no browse tree — `getMetadata` returns nil for
/// every container), so there is no real catalog to walk. Instead we present a
/// curated set of genre rows, each populated by a station search, to give a
/// browse-like experience on top of the one capability the service supports.
@MainActor
@Observable
public final class SonosRadioBrowseService {
    public static let shared = SonosRadioBrowseService()

    /// Genre rows shown on the browse screen, in order. Each is a station-search
    /// term.
    public let genres: [String] = [
        "Pop", "Rock", "Hip-Hop", "Country", "Jazz",
        "Classical", "News", "Sports", "Dance", "Latin"
    ]

    /// Preview stations per genre, used for the section grids.
    public var previews: [String: [PlayableContent]] = [:]
    public var isLoading = false
    public var error: String?

    /// Number of preview stations shown per section before the "see all" link.
    public let previewCount = 6

    private let musicSearchService = MusicSearchService.shared
    private var hasLoaded = false

    private init() {}

    public func load() async {
        guard !isLoading, !hasLoaded else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        await withTaskGroup(of: (String, [PlayableContent]).self) { group in
            for genre in genres {
                group.addTask { [self] in
                    (genre, await musicSearchService.sonosRadioStations(matching: genre, count: 12))
                }
            }
            for await (genre, stations) in group {
                previews[genre] = stations
            }
        }

        hasLoaded = true
        if populatedGenres.isEmpty {
            error = "Couldn't load Sonos Radio. Make sure your Sonos system is reachable and try again."
        }
    }

    public func refresh() async {
        previews = [:]
        error = nil
        hasLoaded = false
        await load()
    }

    /// Genres that returned at least one station, in display order.
    public var populatedGenres: [String] {
        genres.filter { !(previews[$0]?.isEmpty ?? true) }
    }
}
