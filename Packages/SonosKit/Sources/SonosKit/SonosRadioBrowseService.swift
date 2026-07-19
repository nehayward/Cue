import Foundation
import MusicSearchKit

/// A section on the Sonos Radio browse screen. Sections are dynamic — fetched
/// from the service's SMAPI root, matching the curated rows the official
/// controller shows ("Trending Now", "Summertime", …) — with a static set of
/// genre searches as a fallback when the browse tree can't be read.
public struct SonosRadioSection: Identifiable {
    public enum Source: Hashable {
        /// A browsable SMAPI container from the service root.
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
/// Radio's SMAPI root (`getMetadata("root")`) and populates each with the
/// stations inside its container. If the root browse yields nothing (older
/// households where the service is effectively search-only), falls back to a
/// curated set of genre rows populated by station searches.
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
            loaded = await loadFallbackSections()
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

    /// The full station list backing a section's "see all" screen.
    public func allStations(for section: SonosRadioSection) async -> [PlayableContent] {
        switch section.source {
        case .container(let id):
            await musicSearchService.sonosRadioContainerStations(id: id, count: 100)
        case .search(let term):
            await musicSearchService.sonosRadioStations(matching: term, count: 100)
        }
    }

    /// Browses the SMAPI root for the service's curated home sections and
    /// fills each with a preview of its stations. Returns `[]` when the root
    /// exposes no usable containers.
    private func loadDynamicSections() async -> [SonosRadioSection] {
        guard let root = await musicSearchService.sonosRadioBrowse(id: "root") else { return [] }

        // Home sections are enumerable containers. Skip search categories and
        // anything unnamed — those aren't content rows.
        let containers = root.items.filter { item in
            item.isContainer
                && item.canEnumerate
                && !item.title.isEmpty
                && item.itemType.lowercased() != "search"
                && item.id.lowercased() != "search"
        }
        guard !containers.isEmpty else { return [] }

        var loaded = containers.map { SonosRadioSection(title: $0.title, source: .container(id: $0.id)) }
        await withTaskGroup(of: (Int, [PlayableContent]).self) { group in
            for (index, container) in containers.enumerated() {
                group.addTask { [self] in
                    (index, await musicSearchService.sonosRadioContainerStations(
                        id: container.id,
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
