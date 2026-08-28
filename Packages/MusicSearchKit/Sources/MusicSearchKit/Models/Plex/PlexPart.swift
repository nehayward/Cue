
public struct PlexPart: Codable, Sendable {
    public let id: Int
    public let key: String
    public let duration: Int?
    public let file: String
    public let size: Int?
    public let container: String?
    public let hasThumbnail: String?
}
