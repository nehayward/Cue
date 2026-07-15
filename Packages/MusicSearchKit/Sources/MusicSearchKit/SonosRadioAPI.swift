import Foundation

/// Client for Sonos Radio (Sonos' first-party streaming service). Sonos Radio
/// has no public REST API — it is reached through the Sonos Music API (SMAPI)
/// using the household's token/key/householdId plus the controller deviceId,
/// like the favourites flow already used for Deezer.
///
/// Its PresentationMap defines search categories ("station", "show") but no
/// browse tree, so `search` is the only metadata action used.
public final class SonosRadioAPI {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Searches within the search category `id` for `term`. Sonos Radio's
    /// PresentationMap exposes search categories (e.g. `station`) but no browse
    /// tree, so search is the only metadata action used.
    public func search(
        endpoint: URL,
        credentials: SMAPICredentials,
        id: String,
        term: String,
        index: Int = 0,
        count: Int = 50
    ) async -> SMAPIMediaResult? {
        let envelope = SMAPIEnvelope(
            credentials: credentials,
            action: .search(id: id, term: term, index: index, count: count)
        )
        return await perform(endpoint: endpoint, envelope: envelope)
    }

    // MARK: - Transport

    private func perform(endpoint: URL, envelope: SMAPIEnvelope) async -> SMAPIMediaResult? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"http://www.sonos.com/Services/1.1#\(envelope.action.soapAction)\"",
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = envelope.xml.data(using: .utf8)

        do {
            let (data, _) = try await session.data(for: request)
            let xml = String(data: data, encoding: .utf8) ?? ""
            return SMAPIMediaParser.parse(xml: xml)
        } catch {
            // Ignore debounce cancellations; surface real failures.
            if (error as NSError).code != NSURLErrorCancelled {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) request failed: \(error)")
            }
            return nil
        }
    }
}
