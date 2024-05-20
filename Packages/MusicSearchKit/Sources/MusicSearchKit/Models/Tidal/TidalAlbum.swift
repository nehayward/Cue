
public struct TidalAlbum: Codable {
    public let id: String
    public let title: String
    public let imageCover: [TidalImage]
    public let videoCover: [TidalImage]
}
