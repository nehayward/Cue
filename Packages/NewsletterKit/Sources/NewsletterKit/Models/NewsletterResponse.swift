import Foundation

/// Decodes both success (`status`) and error (`error`) bodies the API
/// returns — server uses a flat shape so a single struct handles either.
struct NewsletterResponse: Codable, Sendable {
    let status: String?
    let error: String?
}
