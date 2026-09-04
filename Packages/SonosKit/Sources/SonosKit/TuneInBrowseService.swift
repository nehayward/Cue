import Foundation
import MusicSearchKit

/// A titled run of stations from TuneIn's directory — the "FM" and "AM"
/// halves of the local page.
public struct TuneInStationGroup: Identifiable, Codable, Hashable, Sendable {
    public let title: String
    public var items: [PlayableContent]

    public var id: String { title }

    public init(title: String, items: [PlayableContent]) {
        self.title = title
        self.items = items
    }
}

/// One row of a TuneIn browse page as the app shows it: a station to play,
/// a link to the next page, or a titled group of rows.
public indirect enum TuneInBrowseEntry: Identifiable, Hashable, Sendable {
    case station(PlayableContent)
    case link(title: String, url: URL)
    case group(title: String, entries: [TuneInBrowseEntry])

    public var id: String {
        switch self {
        case .station(let item): "station:\(item.id)"
        case .link(_, let url): "link:\(url.absoluteString)"
        case .group(let title, _): "group:\(title)"
        }
    }
}

/// Backs the Radio tab's TuneIn rows: the stations near the user (placed
/// by IP, grouped FM and AM) and what's trending — cached so the tab
/// paints at once — plus page-by-page browsing of the rest of the
/// directory. Search goes through `MusicSearchService`, which ranks it.
@MainActor
@Observable
public final class TuneInBrowseService {
    public static let shared = TuneInBrowseService()

    public private(set) var localGroups: [TuneInStationGroup] = []
    public private(set) var trending: [PlayableContent] = []
    public var isLoading = false
    public var error: String?

    @ObservationIgnored private let api = TuneInAPI()
    private var hasLoaded = false

    private nonisolated static let localCacheKey = "tuneInLocalStations"
    private nonisolated static let trendingCacheKey = "tuneInTrendingStations"

    private init() {}

    /// Every local station, FM first, for the "see all" list.
    public var localStations: [PlayableContent] {
        localGroups.flatMap(\.items)
    }

    public func load() async {
        guard !isLoading, !hasLoaded else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Last time's stations first, read off the main actor, so the tab
        // has rows while the fetch runs.
        if localGroups.isEmpty, let cached = await Self.cached([TuneInStationGroup].self, key: Self.localCacheKey) {
            localGroups = cached
        }
        if trending.isEmpty, let cached = await Self.cached([PlayableContent].self, key: Self.trendingCacheKey) {
            trending = cached
        }

        async let localPage = api.browse(.local)
        async let trendingPage = api.browse(.trending)
        let local = Self.groups(from: await localPage)
        let popular = Self.stations(in: await trendingPage)

        if !local.isEmpty {
            localGroups = local
            MemoryFileCache.shared.save(local, forKey: Self.localCacheKey)
        }
        if !popular.isEmpty {
            trending = popular
            MemoryFileCache.shared.save(popular, forKey: Self.trendingCacheKey)
        }

        hasLoaded = true
        if localGroups.isEmpty, trending.isEmpty {
            error = "Couldn't reach TuneIn. Check your connection and try again."
        } else if local.isEmpty, popular.isEmpty {
            error = "Couldn't refresh TuneIn — showing your last loaded stations."
        }
    }

    public func refresh() async {
        error = nil
        hasLoaded = false
        await load()
    }

    /// A page of the directory, for the link rows to push.
    public func browse(url: URL) async -> [TuneInBrowseEntry] {
        Self.entries(from: await api.browse(url: url))
    }

    public func browse(_ page: TuneInBrowsePage) async -> [TuneInBrowseEntry] {
        Self.entries(from: await api.browse(page))
    }

    private nonisolated static func cached<T: Codable>(_ type: T.Type, key: String) async -> T? {
        MemoryFileCache.shared.load(forKey: key, as: type)
    }

    // MARK: - Mapping

    /// The local page's blocks as station groups. Stations outside any
    /// block (some regions come flat) form one group ahead of the rest.
    private nonisolated static func groups(from items: [TuneInBrowseItem]) -> [TuneInStationGroup] {
        var groups: [TuneInStationGroup] = []
        var loose: [PlayableContent] = []
        var seen = Set<String>()

        for item in items {
            switch item {
            case .station(let station):
                let content = station.toPlayable
                if seen.insert(content.id).inserted { loose.append(content) }
            case .group(let group):
                let stations = stations(in: group.items).filter { seen.insert($0.id).inserted }
                if !stations.isEmpty {
                    groups.append(TuneInStationGroup(title: group.title, items: stations))
                }
            case .link:
                break
            }
        }
        if !loose.isEmpty {
            groups.insert(TuneInStationGroup(title: "Stations", items: loose), at: 0)
        }
        return groups
    }

    /// Every station on a page, groups flattened, each once.
    private nonisolated static func stations(in items: [TuneInBrowseItem]) -> [PlayableContent] {
        var seen = Set<String>()
        return flattenedStations(in: items).filter { seen.insert($0.id).inserted }
    }

    private nonisolated static func flattenedStations(in items: [TuneInBrowseItem]) -> [PlayableContent] {
        items.flatMap { item -> [PlayableContent] in
            switch item {
            case .station(let station): [station.toPlayable]
            case .group(let group): flattenedStations(in: group.items)
            case .link: []
            }
        }
    }

    private nonisolated static func entries(from items: [TuneInBrowseItem]) -> [TuneInBrowseEntry] {
        items.map { item in
            switch item {
            case .station(let station): .station(station.toPlayable)
            case .link(let link): .link(title: link.title, url: link.url)
            case .group(let group): .group(title: group.title, entries: entries(from: group.items))
            }
        }
    }
}
