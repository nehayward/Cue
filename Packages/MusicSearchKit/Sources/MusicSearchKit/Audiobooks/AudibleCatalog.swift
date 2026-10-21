import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Audible's public catalog search (`api.audible.com/1.0/catalog/products`,
/// which Audiobookshelf's Audible match asks too), for the ASIN of a book
/// its server never matched there: by its title and author, narrowed to
/// the editions as long as the book (`editions(_:fitting:)`). With the
/// ASIN, Audnexus has that edition's chapters (`AudnexusChapters`), which
/// are laid on the book only if its length is the edition's to the second.
public enum AudibleCatalog {
    /// One edition in the catalog.
    public struct Product: Decodable, Sendable {
        public let asin: String
        public let title: String?
        /// Whole minutes.
        public let runtimeLengthMin: Int?

        enum CodingKeys: String, CodingKey {
            case asin, title
            case runtimeLengthMin = "runtime_length_min"
        }
    }

    struct Page: Decodable {
        let products: [Product]?
    }

    /// Each store Audnexus also answers for, by its region.
    static let hosts: [String: String] = [
        "us": "api.audible.com", "ca": "api.audible.ca", "uk": "api.audible.co.uk",
        "au": "api.audible.com.au", "fr": "api.audible.fr", "de": "api.audible.de",
        "jp": "api.audible.co.jp", "it": "api.audible.it", "in": "api.audible.in",
        "es": "api.audible.es"
    ]

    /// The listener's store, else the US one.
    public static func region(for locale: Locale = .current) -> String {
        guard let code = locale.region?.identifier.lowercased() else { return "us" }
        let region = code == "gb" ? "uk" : code
        return hosts[region] == nil ? "us" : region
    }

    /// The title to search by: the part before a subtitle or series, which
    /// servers keep in the title in their own ways ("The Fellowship of the
    /// Ring: Lord of the Rings, Book 1", "… (Lord of the Rings)").
    public static func searchTitle(_ title: String) -> String {
        var short = title.trimmingCharacters(in: .whitespaces)
        for separator in [":", " (", " [", " - ", " – ", " — "] {
            guard let range = short.range(of: separator) else { continue }
            let head = short[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if head.count >= 3 { short = head }
        }
        return short
    }

    /// The ASINs of the editions as long as a book `duration` seconds long,
    /// closest first. Audible gives lengths in whole minutes, so a minute is
    /// allowed beside `AudnexusChapters`' own tolerance, against which the
    /// chapters are checked to the second once fetched.
    public static func editions(_ products: [Product], fitting duration: TimeInterval) -> [String] {
        let slack = AudnexusChapters.tolerance(for: duration) + 60
        return products
            .compactMap { product -> (asin: String, gap: TimeInterval)? in
                guard let minutes = product.runtimeLengthMin, AudnexusChapters.isASIN(product.asin) else { return nil }
                let gap = abs(TimeInterval(minutes * 60) - duration)
                return gap <= slack ? (product.asin, gap) : nil
            }
            .sorted { $0.gap < $1.gap }
            .map(\.asin)
    }

    /// The catalog's address for `title` by `author` in `region`'s store.
    public static func url(title: String, author: String?, region: String = "us") -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = hosts[region] ?? hosts["us"]
        components.path = "/1.0/catalog/products"
        var query = [
            URLQueryItem(name: "num_results", value: "10"),
            URLQueryItem(name: "products_sort_by", value: "Relevance"),
            URLQueryItem(name: "response_groups", value: "product_attrs"),
            URLQueryItem(name: "title", value: title)
        ]
        if let author, !author.isEmpty {
            query.append(URLQueryItem(name: "author", value: author))
        }
        components.queryItems = query
        return components.url
    }

    /// Audible's editions of `title` by `author`; nil when it couldn't be
    /// asked.
    public static func search(title: String, author: String?, region: String = "us") async -> [Product]? {
        guard let url = url(title: title, author: author, region: region) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let page = try? JSONDecoder().decode(Page.self, from: data) else { return nil }
        return page.products ?? []
    }
}
