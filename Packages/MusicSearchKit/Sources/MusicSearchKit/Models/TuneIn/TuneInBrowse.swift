import Foundation

/// One entry of a TuneIn browse page (`Browse.ashx`): a station to play, a
/// link to another page, or a titled group of entries — the "FM" and "AM"
/// blocks a local-radio page is split into.
public enum TuneInBrowseItem: Sendable {
    case station(TuneInStation)
    case link(TuneInBrowseLink)
    case group(TuneInBrowseGroup)
}

/// A link to another browse page — a genre, a region, a curated list.
public struct TuneInBrowseLink: Sendable, Hashable {
    public let title: String
    /// The page's guide id ("c57940", "g22", "r0"). Some links carry only a
    /// URL, so this can be nil; `url` is always browsable.
    public let guideID: String?
    public let url: URL

    public init(title: String, guideID: String?, url: URL) {
        self.title = title
        self.guideID = guideID
        self.url = url
    }
}

/// A titled block of entries inside a page.
public struct TuneInBrowseGroup: Sendable {
    public let title: String
    public let items: [TuneInBrowseItem]

    public init(title: String, items: [TuneInBrowseItem]) {
        self.title = title
        self.items = items
    }
}

/// The pages TuneIn's browse endpoint serves. Categories are the top-level
/// entries of the directory; `id` reaches any page a link points at.
public enum TuneInBrowsePage: Hashable, Sendable {
    /// Stations near the caller, grouped FM and AM. TuneIn places the
    /// request by IP, so no location permission is involved.
    case local
    case trending
    case music
    case sports
    case talk
    /// The directory by region ("r0" is the world).
    case byLocation
    /// The local page for a point rather than for the caller: the Radio
    /// map's Search This Area. `latlon` stands in for the IP.
    case nearby(latitude: Double, longitude: Double)
    case id(String)

    var queryItems: [URLQueryItem] {
        switch self {
        case .local: [URLQueryItem(name: "c", value: "local")]
        case .trending: [URLQueryItem(name: "c", value: "trending")]
        case .music: [URLQueryItem(name: "c", value: "music")]
        case .sports: [URLQueryItem(name: "c", value: "sports")]
        case .talk: [URLQueryItem(name: "c", value: "talk")]
        case .byLocation: [URLQueryItem(name: "id", value: "r0")]
        case let .nearby(latitude, longitude):
            [
                URLQueryItem(name: "c", value: "local"),
                // Four places is about 10 m, closer than any station needs.
                URLQueryItem(name: "latlon", value: String(format: "%.4f,%.4f", latitude, longitude)),
            ]
        case .id(let id): [URLQueryItem(name: "id", value: id)]
        }
    }

    public var url: URL {
        var url = URL(string: "https://opml.radiotime.com/Browse.ashx")!
        url.append(queryItems: queryItems)
        return url
    }
}
