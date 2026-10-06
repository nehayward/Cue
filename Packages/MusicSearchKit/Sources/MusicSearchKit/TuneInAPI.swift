import Foundation
import SWXMLHash

public final class TuneInAPI: Sendable {
    private let session: URLSession
    private let parser = TuneInParser()

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
    }

    public func search(for query: String, limit: Int = 10) async -> [TuneInStation] {
        var searchURL = URL(string: "https://opml.radiotime.com/search.ashx")!
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query)
        ]
        searchURL.append(queryItems: queryItems)

        let request = URLRequest(url: searchURL)
        guard let (data, _) = try? await session.data(for: request) else {
            return []
        }
        return parser.parseStations(xmlData: data)
    }

    /// A page of TuneIn's directory: the stations near the caller, what's
    /// trending, a category, or any page a link points at.
    public func browse(_ page: TuneInBrowsePage) async -> [TuneInBrowseItem] {
        await browse(url: page.url)
    }

    public func browse(url: URL) async -> [TuneInBrowseItem] {
        guard let url = TuneInParser.secured(url),
              let (data, _) = try? await session.data(for: URLRequest(url: url)) else {
            return []
        }
        return parser.parseBrowse(xmlData: data)
    }

    /// The station's streams, for playing it on this device. `Tune.ashx`
    /// without `render=json` answers with a bare playlist file that
    /// `AVPlayer` can't open, so this asks for the JSON form and hands back
    /// the URLs inside it.
    public func streams(for stationID: String) async -> [TuneInStream] {
        var url = URL(string: "https://opml.radiotime.com/Tune.ashx")!
        url.append(queryItems: [
            URLQueryItem(name: "id", value: stationID),
            URLQueryItem(name: "render", value: "json"),
            URLQueryItem(name: "formats", value: "mp3,aac,ogg,hls"),
        ])
        guard let (data, _) = try? await session.data(for: URLRequest(url: url)),
              let response = try? JSONDecoder().decode(TuneInStreamResponse.self, from: data) else {
            return []
        }
        return response.body
    }

    /// The one stream to play, or nil when the station has none.
    public func streamURL(for stationID: String) async -> URL? {
        await streams(for: stationID).preferred?.url
    }

    /// Where a station is, for the Radio map. Nil when TuneIn couldn't be
    /// asked (offline, or turned away twice), so the caller asks again
    /// later; a station TuneIn places nowhere comes back empty.
    public func place(for stationID: String) async -> TuneInPlace? {
        var url = URL(string: "https://opml.radiotime.com/describe.ashx")!
        url.append(queryItems: [URLQueryItem(name: "id", value: stationID)])
        let request = URLRequest(url: url)

        for attempt in 1...2 {
            guard let (data, response) = try? await session.data(for: request) else { return nil }
            // A 403 is TuneIn asking callers to slow down, the way
            // `lookupStation` reads it.
            if (response as? HTTPURLResponse)?.statusCode == 403 {
                if attempt == 1 { try? await Task.sleep(for: .milliseconds(500)) }
                continue
            }
            return parser.parsePlace(xmlData: data)
        }
        return nil
    }

    public func lookupStation(for stationID: String) async -> TuneInStation? {
        var searchURL = URL(string: "https://opml.radiotime.com/describe.ashx")!
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id", value: stationID)
        ]
        searchURL.append(queryItems: queryItems)
        let request = URLRequest(url: searchURL)

        let maxRetries = 3
        var currentRetry = 0

        while currentRetry < maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                    currentRetry += 1
                    try? await Task.sleep(for: .milliseconds(200))// Wait for 2 seconds before retrying
                    continue
                }
                return parser.parseStationDetails(xmlData: data)
            } catch {
                print("Request failed: \(error.localizedDescription). Retry attempt \(currentRetry + 1) out of \(maxRetries).")
                currentRetry += 1
                try? await Task.sleep(for: .milliseconds(200))// Wait for 2 seconds before retrying
            }
        }
        return nil
    }
}
