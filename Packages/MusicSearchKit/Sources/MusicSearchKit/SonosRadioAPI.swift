import Foundation

/// Client for Sonos Radio (Sonos' first-party streaming service). Sonos Radio
/// has no public REST API — it is reached through the Sonos Music API (SMAPI)
/// using the household's token/key/householdId plus the controller deviceId,
/// like the favourites flow already used for Deezer.
///
/// Two metadata actions are used: `getMetadata` to browse the service's
/// container tree (the root exposes the dynamic home sections the official
/// controller shows — "Trending Now", "Summertime", …) and `search` within
/// the PresentationMap's search categories ("station", "show").
public final class SonosRadioAPI {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Browses the children of container `id` ("root" for the service root).
    /// Root children are the curated home sections; each section is itself a
    /// container whose children are playable stations.
    public func getMetadata(
        endpoint: URL,
        credentials: SMAPICredentials,
        id: String,
        index: Int = 0,
        count: Int = 100
    ) async -> SMAPIMediaResult? {
        let envelope = SMAPIEnvelope(
            credentials: credentials,
            action: .getMetadata(id: id, index: index, count: count)
        )
        return await perform(endpoint: endpoint, envelope: envelope)
    }

    /// Searches within the search category `id` for `term`.
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
            let (data, response) = try await session.data(for: request)
            let xml = String(data: data, encoding: .utf8) ?? ""
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            // Diagnostics: a SOAP fault body contains no media items, which is
            // otherwise indistinguishable from a genuinely empty container.
            if !(200...299).contains(status) {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) HTTP \(status) from \(endpoint): \(xml.prefix(1000))")
            }
            if let fault = Self.faultString(in: xml) {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) fault: \(fault)")
                return nil
            }

            let result = SMAPIMediaParser.parse(xml: xml)
            if case .getMetadata = envelope.action {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) HTTP \(status) from \(endpoint), parsed \(result?.items.count ?? -1) items (total \(result?.total ?? -1))")
                print("Sonos Radio SMAPI \(envelope.action.soapAction) response body: \(xml.prefix(4000))")
            }
            return result
        } catch {
            // Ignore debounce cancellations; surface real failures.
            if (error as NSError).code != NSURLErrorCancelled {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) request failed: \(error)")
            }
            return nil
        }
    }

    /// Extracts the `<faultstring>` from a SOAP fault body, if present.
    private static func faultString(in xml: String) -> String? {
        guard let start = xml.range(of: "<faultstring>"),
              let end = xml.range(of: "</faultstring>"),
              start.upperBound <= end.lowerBound else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
    }
}
