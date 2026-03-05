import Foundation

/// Response from creating a drop.
public struct DropResponse: Codable, Sendable {
    /// The 6-character code to share.
    public let code: String
    /// Time to live in seconds.
    public let ttl: Int
    /// URL to a QR code image for the code.
    public let image: String
}
