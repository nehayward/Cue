import Foundation

public struct MediaContent: Equatable {
    public let service: MusicService
    public let id: String
    public let type: ContentType
    public let location: URL
}
