import Foundation

public struct MediaContent: Equatable, Codable, Hashable {
    public let service: MusicService
    public let id: String
    public let type: ContentType
    public let location: URL?

    public init(service: MusicService, id: String, type: ContentType, location: URL?) {
        self.service = service
        self.id = id
        self.type = type
        self.location = location
    }
}
