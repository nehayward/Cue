public struct PlexContainer<Container: Codable>: Codable {
    public let mediaContainer: Container
    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}
