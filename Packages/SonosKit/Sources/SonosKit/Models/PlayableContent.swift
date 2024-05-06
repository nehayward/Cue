import Foundation
import CoreTransferable
import UniformTypeIdentifiers

public struct PlayableContent: Equatable, Codable, Hashable, Identifiable {
    public var id: String { content.id }
    public let title: String
    public let subtitle: String
    public let artwork: URL?
    public let content: MediaContent
    public let duration: Duration?
    public let popularity: Int?
    public let metadata: PlayableContentMetadata?

    public var shareURL: URL {
        guard let musicService = content.service.name else { return URL(string: "clic://")! }
        return URL(string: "clic://play/\(musicService)/\(content.type)/\(id)")!
    }

    public init(
        title: String,
        subtitle: String,
        artwork: URL?,
        content: MediaContent,
        duration: Duration? = nil,
        popularity: Int? = nil,
        metadata: PlayableContentMetadata? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.content = content
        self.duration = duration
        self.popularity = popularity
        self.metadata = metadata
    }
}

extension PlayableContent: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .playableContent)
        ProxyRepresentation(exporting: \.shareURL)
    }
}

extension UTType {
    public static var playableContent: UTType { UTType(exportedAs: "com.clic.playableContent") }
}
