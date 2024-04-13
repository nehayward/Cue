import Foundation

public struct PlayableContent: Equatable, Codable, Hashable, Identifiable {
    public var id: String { content.id }
    public let title: String
    public let subtitle: String
    public let artwork: URL?
    public let content: MediaContent
    public let duration: Duration?
    public let popularity: Int?

    public init(
        title: String,
        subtitle: String,
        artwork: URL?,
        content: MediaContent,
        duration: Duration? = nil,
        popularity: Int? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.content = content
        self.duration = duration
        self.popularity = popularity
    }
}
