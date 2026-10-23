import Foundation
import os

/// Client for Pandora on Sonos. Pandora is reached purely over the Sonos SMAPI
/// protocol — browse (`getMetadata`) for the user's stations and `search`
/// within the service's search categories — using the household's stored
/// loginToken/key plus the controller deviceId, exactly like Sonos Radio.
///
/// Token refresh is shared with Sonos Radio through `SMAPILoginSession`.
public final class PandoraAPI: Sendable {
    private let session: URLSession
    private let login: SMAPILoginSession

    public init(
        session: URLSession = .shared,
        onTokenRefreshed: (@Sendable (_ token: String, _ key: String) -> Void)? = nil
    ) {
        self.session = session
        self.login = SMAPILoginSession(onTokenRefreshed: onTokenRefreshed)
    }

    // MARK: - SMAPI (SOAP)

    /// Browses a container (`"root"` for the top level, `"search"` for the
    /// search-category list, or a container id from a prior browse).
    public func getMetadata(
        endpoint: URL,
        credentials: SMAPICredentials,
        id: String,
        index: Int = 0,
        count: Int = 100
    ) async -> SMAPIMediaResult? {
        await performParsed(
            endpoint: endpoint,
            credentials: credentials,
            action: .getMetadata(id: id, index: index, count: count)
        )
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
        await performParsed(
            endpoint: endpoint,
            credentials: credentials,
            action: .search(id: id, term: term, index: index, count: count)
        )
    }

    /// Rates the currently playing track — Pandora's thumbs up / thumbs down.
    /// `id` is the track's SMAPI id (the `x-sonos-http:` stream id, minus the
    /// file extension), not the station id. Returns whether the service
    /// accepted the rating.
    public func rateItem(
        endpoint: URL,
        credentials: SMAPICredentials,
        id: String,
        rating: Int
    ) async -> Bool {
        await performRaw(
            endpoint: endpoint,
            credentials: credentials,
            action: .rateItem(id: id, rating: rating)
        ) != nil
    }

    /// Runs `action` with the freshest known login; on an expired-token fault,
    /// refreshes through SMAPI (the same flow the official controller uses)
    /// and retries once with the new token.
    private func performParsed(
        endpoint: URL,
        credentials: SMAPICredentials,
        action: SMAPIAction
    ) async -> SMAPIMediaResult? {
        await performRaw(endpoint: endpoint, credentials: credentials, action: action)
            .flatMap { SMAPIMediaParser.parse(xml: $0) }
    }

    /// The refresh-and-retry wrapper shared by every SMAPI call: returns the
    /// raw response XML, or nil if the request failed for a reason a token
    /// refresh can't fix.
    private func performRaw(
        endpoint: URL,
        credentials: SMAPICredentials,
        action: SMAPIAction
    ) async -> String? {
        let attempted = effectiveCredentials(credentials)
        let (xml, authFailed) = await perform(
            endpoint: endpoint,
            envelope: SMAPIEnvelope(credentials: attempted, action: action)
        )
        if let xml { return xml }
        guard authFailed else { return nil }

        guard await refreshLogin(afterFailureOf: attempted.token, endpoint: endpoint, credentials: credentials) else {
            return nil
        }
        return await perform(
            endpoint: endpoint,
            envelope: SMAPIEnvelope(credentials: effectiveCredentials(credentials), action: action)
        ).xml
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
        let (xml, _) = await perform(endpoint: endpoint, envelope: envelope)
        guard let xml,
              let token = Self.tagValue("authToken", in: xml),
              let key = Self.tagValue("privateKey", in: xml) else {
            print("Pandora refreshAuthToken did not return a new token")
            return nil
        }
        return (token, key)
    }

    // MARK: - Transport

    /// Performs a SOAP request. Returns the response XML on success, or
    /// `authFailed: true` when the service faulted asking for a token refresh
    /// (SMAPI's `tokenRefreshRequired` / expired-credentials faults).
    private func perform(endpoint: URL, envelope: SMAPIEnvelope) async -> (xml: String?, authFailed: Bool) {
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
            if let fault = Self.tagValue("faultstring", in: xml) {
                let faultcode = Self.tagValue("faultcode", in: xml) ?? ""
                if Self.isAuthFault(code: faultcode, message: fault) || status == 401 {
                    print("Pandora SMAPI \(envelope.action.soapAction) auth fault (\(fault)) — refreshing token")
                    return (nil, true)
                }
                print("Pandora SMAPI \(envelope.action.soapAction) fault: \(fault)")
                return (nil, false)
            }
            if status == 401 || status == 403 {
                return (nil, true)
            }
            return (xml, false)
        } catch {
            // Ignore debounce cancellations; surface real failures.
            if (error as NSError).code != NSURLErrorCancelled {
                print("Pandora SMAPI \(envelope.action.soapAction) request failed: \(error)")
            }
            return (nil, false)
        }
    }

    /// Whether a SOAP fault means the loginToken expired and should be
    /// refreshed (SMAPI signals this with `Client.TokenRefreshRequired` /
    /// `AuthTokenExpired` style faults).
    private static func isAuthFault(code: String, message: String) -> Bool {
        let haystack = (code + " " + message).lowercased()
        return haystack.contains("tokenrefreshrequired")
            || haystack.contains("authtokenexpired")
            || haystack.contains("loginunauthorized")
            || haystack.contains("sessionidinvalid")
    }

    // MARK: - Helpers

    private func effectiveCredentials(_ credentials: SMAPICredentials) -> SMAPICredentials {
        login.effectiveCredentials(credentials)
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
