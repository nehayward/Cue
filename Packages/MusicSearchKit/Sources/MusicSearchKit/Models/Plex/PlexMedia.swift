

public struct PlexMedia: Codable {
    public let id: Int
    public let duration: Int
    public let bitrate: Int
    public let audioChannels: Int
    public let audioCodec: String
    public let container: String
    public let part: [PlexPart]

    enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, audioChannels, audioCodec, container
        case part = "Part"
    }
}
