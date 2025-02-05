
public struct TidalPlaylistResource: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let numberOfTracks: Int?
    public let duration: Int
    public let imageUrls: [TidalImage]
    public let tidalUrl: String?
}
