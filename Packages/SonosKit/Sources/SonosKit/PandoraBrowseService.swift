import Foundation
import MusicSearchKit

/// A section on the Pandora browse screen — one of the service's root SMAPI
/// containers ("My Stations", "Browse", …) with its preview stations.
public struct PandoraSection: Identifiable, Codable, Sendable {
    /// The container's SMAPI id, browsed for the full "see all" list.
    public let id: String
    public let title: String
    public var items: [PlayableContent] = []
}

/// Backs `PandoraBrowseScreen`. Pandora is browsed over plain SMAPI: the root
/// `getMetadata` call returns the service's containers (the user's stations
/// list first), and each container's items become a section's stations.
@MainActor
@Observable
public final class PandoraBrowseService {
    public static let shared = PandoraBrowseService()

    /// Sections shown on the browse screen, in the order the service returns
    /// its root containers.
    public private(set) var sections: [PandoraSection] = []
    public var isLoading = false
    public var error: String?

    /// Number of preview stations shown per section before the "see all" link.
    public let previewCount = 12
    /// Stations fetched per section for the preview grids.
    private let sectionFetchCount = 14

    private let musicSearchService = MusicSearchService.shared
    private var hasLoaded = false
    /// When the sections on screen were last fetched. Revisiting the screen
    /// after `staleAfter` refetches instead of trusting `hasLoaded` for the
    /// whole session — stations appear on the account without Cue doing
    /// anything (playing a search seed creates one, and so does the Pandora
    /// app or another controller), and a session-long cache hid them until a
    /// manual pull-to-refresh.
    private var lastLoaded: Date?
    private let staleAfter: TimeInterval = 300
    /// Session cache of full station lists per container id, so re-entering a
    /// "see all" screen doesn't refetch.
    private var sectionStationsCache: [String: [PlayableContent]] = [:]

    private nonisolated static let cacheKey = "pandoraBrowseSections"

    private init() {}

    public func load() async {
        guard !isLoading else { return }
        // Already loaded and still fresh — nothing to do. When it's gone stale
        // the current sections stay on screen while the refetch runs.
        if hasLoaded, let lastLoaded, Date().timeIntervalSince(lastLoaded) < staleAfter { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Hydrate the last-fetched sections first — read off the main actor —
        // so the screen paints instantly while the fresh fetch runs.
        if sections.isEmpty, let cached = await Self.loadCachedSections() {
            sections = cached
        }

        let fresh = await loadSections()
        // Switching to another service mid-load cancels the screen's task, and
        // the cancelled requests come back empty. Recording that as a fresh
        // load kept Pandora on "Couldn't load" until it went stale; leave it
        // unloaded so the next visit tries again.
        guard !Task.isCancelled else { return }
        if !fresh.isEmpty {
            sections = fresh
            MemoryFileCache.shared.save(fresh, forKey: Self.cacheKey)
        } else if !sections.isEmpty {
            // The fetch failed but cached sections are on screen — surface it
            // instead of silently showing stale rows.
            error = "Couldn't refresh Pandora — showing your last loaded stations."
        }

        hasLoaded = true
        lastLoaded = Date()
        if populatedSections.isEmpty {
            error = "Couldn't load Pandora. Make sure Pandora is set up in the Sonos app and try again."
        }
    }

    /// Reads the persisted sections off the main actor (disk IO + JSON
    /// decode), so hydration never blocks view setup.
    private nonisolated static func loadCachedSections() async -> [PandoraSection]? {
        MemoryFileCache.shared.load(forKey: cacheKey, as: [PandoraSection].self)
    }

    public func refresh() async {
        // Keep the current sections on screen until fresh ones arrive.
        error = nil
        hasLoaded = false
        lastLoaded = nil
        sectionStationsCache = [:]
        await load()
    }

    /// Sections that have at least one station, in display order.
    public var populatedSections: [PandoraSection] {
        sections.filter { !$0.items.isEmpty }
    }

    /// The full station list backing a section's "see all" screen. Browses the
    /// section's container id; if that returns nothing, the inline preview
    /// items are shown instead.
    public func allStations(for section: PandoraSection) async -> [PlayableContent] {
        if let cached = sectionStationsCache[section.id] { return cached }
        let stations = await stations(in: section.id, count: 100)
        // Don't cache the degraded preview fallback — a transient failure
        // would otherwise cap this section at its previews all session.
        guard !stations.isEmpty else { return section.items }
        sectionStationsCache[section.id] = stations
        return stations
    }

    /// Browses the SMAPI root and turns each container into a section with its
    /// preview stations. Pandora's root returns one container ("My Stations",
    /// id `myStations`); stations sitting directly at the root land in a
    /// leading "My Stations" section as a fallback.
    ///
    /// Note on shapes (from a capture of the official controller): stations
    /// arrive as `mediaCollection` elements with `itemType` "program" and
    /// `canPlay` true / `canEnumerate` false, so "is a station" is decided by
    /// `canPlay` — NOT by mediaMetadata vs mediaCollection. Real containers
    /// ("My Stations", "Stations (A-Z)") have `canPlay` false.
    private func loadSections() async -> [PandoraSection] {
        guard let root = await musicSearchService.pandoraBrowse(id: "root", count: 100) else {
            print("Pandora browse: root fetch failed")
            return []
        }

        var loaded: [PandoraSection] = []
        let rootStations = root.items.filter(\.canPlay)
        if !rootStations.isEmpty {
            loaded.append(PandoraSection(
                id: "root",
                title: "My Stations",
                items: rootStations.map { musicSearchService.pandoraContent(from: $0, summaryIsArtist: false) }
            ))
        }

        // Drop duplicate titles: RouterDestination.playableList identity is
        // keyed on title, so two same-titled sections would collapse onto one
        // navigation destination.
        var seenTitles = Set(loaded.map(\.title))
        let containers = root.items.filter { !$0.canPlay && $0.canEnumerate && $0.id != "search" }
            .filter { seenTitles.insert($0.title).inserted }
        var containerSections = containers.map { PandoraSection(id: $0.id, title: $0.title) }

        await withTaskGroup(of: (Int, [PlayableContent]).self) { group in
            for (index, container) in containers.enumerated() {
                group.addTask { [self] in
                    (index, await stations(in: container.id, count: sectionFetchCount))
                }
            }
            for await (index, items) in group {
                containerSections[index].items = items
            }
        }

        loaded.append(contentsOf: containerSections)
        return loaded.filter { !$0.items.isEmpty }
    }

    /// The playable stations inside a container. Descends one level into
    /// sub-containers (e.g. "Stations (A-Z)") so a section still previews
    /// something useful without a request storm.
    private func stations(in containerID: String, count: Int) async -> [PlayableContent] {
        guard let result = await musicSearchService.pandoraBrowse(id: containerID, count: count) else {
            return []
        }
        let direct = result.items.filter(\.canPlay)
        if !direct.isEmpty {
            return direct.map { musicSearchService.pandoraContent(from: $0, summaryIsArtist: false) }
        }
        // One level down: take the first sub-container that yields stations.
        for sub in result.items.filter({ !$0.canPlay && $0.canEnumerate }).prefix(3) {
            if let nested = await musicSearchService.pandoraBrowse(id: sub.id, count: count) {
                let stations = nested.items.filter(\.canPlay)
                if !stations.isEmpty {
                    return stations.map { musicSearchService.pandoraContent(from: $0, summaryIsArtist: false) }
                }
            }
        }
        return []
    }
}
