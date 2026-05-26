import Foundation

/// Errors that can occur during a newsletter subscribe call.
public enum NewsletterError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidEmail
    case networkError(String)
    case decodingError(String)
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidEmail:
            return "That doesn't look like a valid email."
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return message
        }
    }
}
