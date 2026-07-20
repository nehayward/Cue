import Foundation
import MusicSearchKit

/// A section on the Sonos Radio browse screen. Sections are dynamic — fetched
/// from the service's browse endpoint, matching the curated rows the official
/// controller shows ("Trending Now", "Summertime", …) — with a static set of
/// genre searches as a fallback when the home fetch fails.
public struct SonosRadioSection: Identifiable {
    public enum Source: Hashable {
        /// A browsable section object id from the home endpoint.
        case container(id: String)
        /// A station-search term (fallback when no browse tree is available).
        case search(term: String)
    }

    public let title: String
    public let source: Source
    public var items: [PlayableContent] = []

    public var id: String {
        switch source {
        case .container(let id): "container:\(id)"
        case .search(let term): "search:\(term)"
        }
    }
}

/// Backs `SonosRadioBrowseScreen`. Loads the dynamic home sections from Sonos
/// Radio's browse REST endpoint (the same `GET /browse/v1` call the official
/// controller makes), which returns every curated section with its preview
/// stations inline. If that fetch fails, falls back to a curated set of genre
/// rows populated by station searches.
@MainActor
@Observable
public final class SonosRadioBrowseService {
    public static let shared = SonosRadioBrowseService()

    /// Fallback genre rows, in order. Each is a station-search term, used only
    /// when the dynamic root browse returns no sections.
    public let fallbackGenres: [String] = [
        "Pop", "Rock", "Hip-Hop", "Country", "Jazz",
        "Classical", "News", "Sports", "Dance", "Latin"
    ]

    /// Sections shown on the browse screen, in the order the service returns
    /// them (or fallback-genre order).
    public private(set) var sections: [SonosRadioSection] = []
    public var isLoading = false
    public var error: String?

    /// Number of preview stations shown per section before the "see all" link.
    public let previewCount = 6
    /// Stations fetched per section for the preview grids.
    private let sectionFetchCount = 12

    private let musicSearchService = MusicSearchService.shared
    private var hasLoaded = false

    private init() {}

    public func load() async {
        guard !isLoading, !hasLoaded else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        var loaded = await loadDynamicSections()
        if loaded.allSatisfy(\.items.isEmpty) {
            print("Sonos Radio browse: no dynamic sections, falling back to genre searches")
            loaded = await loadFallbackSections()
        } else {
            print("Sonos Radio browse: dynamic sections loaded: \(loaded.map { "\($0.title) (\($0.items.count))" }.joined(separator: ", "))")
        }
        sections = loaded

        hasLoaded = true
        if populatedSections.isEmpty {
            error = "Couldn't load Sonos Radio. Make sure your Sonos system is reachable and try again."
        }
    }

    public func refresh() async {
        sections = []
        error = nil
        hasLoaded = false
        await load()
    }

    /// Sections that have at least one station, in display order.
    public var populatedSections: [SonosRadioSection] {
        sections.filter { !$0.items.isEmpty }
    }

    /// The full station list backing a section's "see all" screen. For a
    /// dynamic section, browses the section's object id; if that returns
    /// nothing, the inline preview items are shown instead.
    public func allStations(for section: SonosRadioSection) async -> [PlayableContent] {
        switch section.source {
        case .container(let id):
            let stations = await musicSearchService.sonosRadioSectionStations(id: id)
            return stations.isEmpty ? section.items : stations
        case .search(let term):
            return await musicSearchService.sonosRadioStations(matching: term, count: 100)
        }
    }

    /// Fetches the curated home sections from the browse REST endpoint. One
    /// request returns every section with its preview stations inline.
    /// Sections without playable items (e.g. the "Browse Radio" category
    /// list) are dropped.
    private func loadDynamicSections() async -> [SonosRadioSection] {
        guard let home = await musicSearchService.sonosRadioHomeSections() else {
            print("Sonos Radio browse: home sections fetch failed")
            return []
        }
        return home.compactMap { section -> SonosRadioSection? in
            let items = section.items
                .filter(\.canPlay)
                .map { musicSearchService.sonosRadioContent(from: $0) }
            guard !items.isEmpty else { return nil }
            return SonosRadioSection(title: section.title, source: .container(id: section.id), items: items)
        }
    }

    /// Static genre rows populated by station searches — the pre-browse-tree
    /// behaviour, kept as a fallback.
    private func loadFallbackSections() async -> [SonosRadioSection] {
        var loaded = fallbackGenres.map { SonosRadioSection(title: $0, source: .search(term: $0)) }
        await withTaskGroup(of: (Int, [PlayableContent]).self) { group in
            for (index, genre) in fallbackGenres.enumerated() {
                group.addTask { [self] in
                    (index, await musicSearchService.sonosRadioStations(
                        matching: genre,
                        count: sectionFetchCount
                    ))
                }
            }
            for await (index, items) in group {
                loaded[index].items = items
            }
        }
        return loaded
    }
}
