import Foundation

/// A service for subscribing email addresses to the Cue newsletter.
/// Mirrors `DropService`'s static-namespace pattern.
public enum NewsletterService {
    private static let baseURL = "https://api.cue.dance/newsletter/subscribe"

    /// Distinguishes a brand-new signup from an idempotent re-submit of an
    /// email already on the list. Both are "success" for the caller — just
    /// surface different UI copy.
    public enum SubscribeResult: Sendable {
        /// Confirmation email sent by Buttondown.
        case subscribed
        /// Email was already on the list; server returned 200 with
        /// `{"status":"already_subscribed"}`.
        case alreadySubscribed
    }

    /// Subscribes the given email to the Cue newsletter.
    /// - Parameters:
    ///   - email: User-entered email. Server normalizes (trim + lowercase);
    ///     trimming client-side first is recommended but not required.
    ///   - source: Tag passed to Buttondown so signups can be segmented by
    ///     origin later (default `"ios"`; pass `"ios-onboarding"`,
    ///     `"ios-preferences"`, etc. to split further).
    /// - Returns: `.subscribed` for new signups, `.alreadySubscribed` if the
    ///   address was already on the list.
    /// - Throws: `NewsletterError` for network failures, invalid email,
    ///   server errors, or decoding issues.
    public static func subscribe(
        email: String,
        source: String = "ios"
    ) async throws -> SubscribeResult {
        guard let url = URL(string: baseURL) else {
            throw NewsletterError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(
                SubscribeRequest(email: email, source: source)
            )
        } catch {
            throw NewsletterError.decodingError(error.localizedDescription)
        }

        return try await perform(request)
    }

    private static func perform(_ request: URLRequest) async throws -> SubscribeResult {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NewsletterError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NewsletterError.invalidResponse
        }

        // The server always returns a JSON body — even on errors — with
        // either `status` (success) or `error` (failure). Decoding is best-
        // effort; if the body is malformed we still classify by status code.
        let body = try? JSONDecoder().decode(NewsletterResponse.self, from: data)

        switch httpResponse.statusCode {
        case 200:
            switch body?.status {
            case "already_subscribed": return .alreadySubscribed
            default: return .subscribed
            }
        case 400:
            throw NewsletterError.invalidEmail
        default:
            throw NewsletterError.serverError(body?.error ?? "Subscribe failed")
        }
    }
}

private struct SubscribeRequest: Encodable, Sendable {
    let email: String
    let source: String
}
