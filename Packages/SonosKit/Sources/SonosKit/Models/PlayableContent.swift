import Foundation

public struct PlayableContent: Equatable, Codable, Hashable {
    public let title: String
    public let subtitle: String
    public let artwork: URL?
    public let content: MediaContent

    public init(title: String, subtitle: String, artwork: URL?, content: MediaContent) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.content = content
    }
}
