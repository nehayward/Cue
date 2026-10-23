import Foundation
import os

/// Client for Sonos Radio (Sonos' first-party streaming service). Sonos Radio
/// has no public REST API — it is reached with the household's SMAPI
/// token/key/householdId plus the controller deviceId, like the favourites
/// flow already used for Deezer.
///
/// Two surfaces are used, both on the SMAPI host:
/// - `GET /browse/v1` — the JSON browse endpoint the official controller uses
///   for the curated home sections ("Trending Now", "Summertime", …), with the
///   SMAPI token as a Bearer credential.
/// - `POST /smapi` — SOAP, for `search` within the PresentationMap's search
///   categories ("station", "show") and for `refreshAuthToken` when the
///   browse endpoint rejects an expired token.
///
/// Token refresh is shared with Pandora and SiriusXM through
/// `SMAPILoginSession`.
public final class SonosRadioAPI: Sendable {
    private let session: URLSession

    private let login: SMAPILoginSession

    public init(
        session: URLSession = .shared,
        onTokenRefreshed: (@Sendable (_ token: String, _ key: String) -> Void)? = nil
    ) {
        self.session = session
        self.login = SMAPILoginSession(onTokenRefreshed: onTokenRefreshed)
    }

    // MARK: - Home browse (REST)

    /// Fetches the curated home sections shown in the official controller.
    /// Refreshes the auth token and retries once on 401/403.
    public func homeSections(
        smapiEndpoint: URL,
        credentials: SMAPICredentials
    ) async -> [SonosRadioHomeSection]? {
        await browse(path: "/browse/v1", smapiEndpoint: smapiEndpoint, credentials: credentials)?.sections
    }

    /// Fetches a home section's full item list. `sectionID` is the section's
    /// browse object id (a path like "/stations/en-US/US/…").
    public func sectionItems(
        sectionID: String,
        smapiEndpoint: URL,
        credentials: SMAPICredentials
    ) async -> [SonosRadioHomeItem]? {
        await browse(
            path: "/browse/v1" + sectionID,
            smapiEndpoint: smapiEndpoint,
            credentials: credentials
        )?.flattenedItems
    }

    private func browse(
        path: String,
        smapiEndpoint: URL,
        credentials: SMAPICredentials
    ) async -> SonosRadioBrowseResponse? {
        guard var components = URLComponents(url: smapiEndpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path
        components.query = nil
        guard let url = components.url else { return nil }

        let attempted = effectiveCredentials(credentials)
        let (response, unauthorized) = await fetchBrowse(url: url, credentials: attempted)
        if let response { return response }
        guard unauthorized else { return nil }

        // Expired token — refresh through SMAPI (the same flow the official
        // controller uses) and retry once with the fresh token.
        guard await refreshLogin(afterFailureOf: attempted.token, endpoint: smapiEndpoint, credentials: credentials) else {
            return nil
        }
        return await fetchBrowse(url: url, credentials: effectiveCredentials(credentials)).response
    }

    private func fetchBrowse(
        url: URL,
        credentials: SMAPICredentials
    ) async -> (response: SonosRadioBrowseResponse?, unauthorized: Bool) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        // The official controller sends the household id in this header.
        request.setValue(credentials.householdId, forHTTPHeaderField: "X-Sonos-Device-Id")
        request.setValue(Self.timeZoneOffset, forHTTPHeaderField: "X-Sonos-Context-TimeZone")
        request.setValue(Locale.preferredLanguages.first ?? "en-US", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 401 || status == 403 {
                print("Sonos Radio browse \(url.path) HTTP \(status) — refreshing auth token")
                return (nil, true)
            }
            guard (200...299).contains(status) else {
                print("Sonos Radio browse \(url.path) HTTP \(status): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
                return (nil, false)
            }
            return (try JSONDecoder().decode(SonosRadioBrowseResponse.self, from: data), false)
        } catch {
            if (error as NSError).code != NSURLErrorCancelled {
                print("Sonos Radio browse \(url.path) failed: \(error)")
            }
            return (nil, false)
        }
    }

    // MARK: - SMAPI (SOAP)

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
            credentials: effectiveCredentials(credentials),
            action: .search(id: id, term: term, index: index, count: count)
        )
        guard let xml = await perform(endpoint: endpoint, envelope: envelope) else { return nil }
        return SMAPIMediaParser.parse(xml: xml)
    }

    /// Refreshes the login after a request using `failedToken` was rejected
    /// (see `SMAPILoginSession`).
    private func refreshLogin(
        afterFailureOf failedToken: String,
        endpoint: URL,
        credentials: SMAPICredentials
    ) async -> Bool {
        await login.refresh(afterFailureOf: failedToken, credentials: credentials) { current in
            await self.requestRefreshedLogin(endpoint: endpoint, credentials: current)
        }
    }

    /// Exchanges the current loginToken for a fresh authToken/privateKey pair.
    private func requestRefreshedLogin(
        endpoint: URL,
        credentials: SMAPICredentials
    ) async -> (token: String, key: String)? {
        let envelope = SMAPIEnvelope(credentials: credentials, action: .refreshAuthToken)
        guard let xml = await perform(endpoint: endpoint, envelope: envelope),
              let token = Self.tagValue("authToken", in: xml),
              let key = Self.tagValue("privateKey", in: xml) else {
            print("Sonos Radio refreshAuthToken did not return a new token")
            return nil
        }
        return (token, key)
    }

    // MARK: - Transport

    /// Performs a SOAP request and returns the raw response XML, or nil on a
    /// transport error or SOAP fault (the fault is logged).
    private func perform(endpoint: URL, envelope: SMAPIEnvelope) async -> String? {
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
            if let fault = Self.tagValue("faultstring", in: xml) {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) fault: \(fault)")
                return nil
            }
            return xml
        } catch {
            // Ignore debounce cancellations; surface real failures.
            if (error as NSError).code != NSURLErrorCancelled {
                print("Sonos Radio SMAPI \(envelope.action.soapAction) request failed: \(error)")
            }
            return nil
        }
    }

    // MARK: - Helpers

    private func effectiveCredentials(_ credentials: SMAPICredentials) -> SMAPICredentials {
        login.effectiveCredentials(credentials)
    }

    /// The local UTC offset in the header format the controller sends
    /// (e.g. "-7:00").
    private static var timeZoneOffset: String {
        let seconds = TimeZone.current.secondsFromGMT()
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        return "\(sign)\(magnitude / 3600):\(String(format: "%02d", (magnitude % 3600) / 60))"
    }

    /// Extracts the text content of the first `<tag>…</tag>` pair.
    private static func tagValue(_ tag: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>"),
              start.upperBound <= end.lowerBound else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
    }
}
