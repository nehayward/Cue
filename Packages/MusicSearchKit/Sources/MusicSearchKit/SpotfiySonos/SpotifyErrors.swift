import Foundation

public enum SpotifyMetadataError: LocalizedError {
    case invalidResponse
    case tokenRefreshFailed
    case serverError(Int)
    case parsingError
    case missingTokenHandler
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        case .serverError(let code):
            return "Server returned status code \(code)"
        case .parsingError:
            return "Failed to parse server response"
        case .missingTokenHandler:
            return "Token refresh handler is not configured"
        }
    }
}
