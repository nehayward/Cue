import Foundation

/// Errors that can occur during Sonos WebSocket operations
enum SonosWebSocketError: Error {
    /// Authentication failed
    case unauthorized(String)
    /// Connection to the Sonos device failed
    case connectionError(String)
    /// Operation timed out
    case timeout
    /// An unknown error occurred
    case unknown(String)
    /// WebSocket specific error
    case websocketError(String)
    /// Operation not supported by the device
    case unsupported(String)
} 