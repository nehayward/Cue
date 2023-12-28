import Foundation

public struct PlayableContent: Equatable {
    public let title: String
    public let subtitle: String
    public let artwork: URL?
    public let content: MediaContent
}
