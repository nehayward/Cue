
public struct TidalArtistResource: Codable {
    public let id: String
    public let name: String
    public let picture: [TidalImage]
    public let main: Bool?
    public let tidalUrl: String?
    public let popularity: Double
}
