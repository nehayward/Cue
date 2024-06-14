import Foundation
import SWXMLHash

public final class TuneInAPI {
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
