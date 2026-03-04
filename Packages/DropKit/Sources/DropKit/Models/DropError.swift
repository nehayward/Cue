import Foundation

/// Errors that can occur during drop/pickup operations.
public enum DropError: Error, LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case invalidResponse
    case serverError(String)
    case codeNotFound
    case codeExpired

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return message
        case .codeNotFound:
            return "Code not found"
        case .codeExpired:
            return "Code has expired"
        }
    }
}
