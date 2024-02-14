import Foundation

public struct Playable: Equatable, Codable, Hashable {
    public let title: String
    public let subtitle: String
    public let artwork: URL?
    public let service: MediaSearchService
    public let id: String
    public let kind: MediaKind
    public let location: URL?

    init(title: String, subtitle: String, artwork: URL?, service: MediaSearchService, id: String, kind: MediaKind, location: URL?) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.service = service
        self.id = id
        self.kind = kind
        self.location = location
    }
}
