//
//  PlayableContent.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/20/24.
//


import Foundation
import CoreTransferable
import UniformTypeIdentifiers

public struct PlayableContent: Equatable, Codable, Hashable, Identifiable, Sendable {
    public var id: String { content.id }
    public let title: String
    public let subtitle: String
    public let thumbnail: URL?
    public let artwork: URL?
    public let content: MediaContent
    public var metadata: PlayableContentMetadata?
    
    public var trackID: String { "\(content.id).\(metadata?.position?.description ?? "")" }
    
    public var radioID: String {
        id.replacingOccurrences(of: ".radio", with: "")
    }
    
    public init(
        title: String,
        subtitle: String,
        thumbnail: URL?,
        artwork: URL?,
        content: MediaContent,
        metadata: PlayableContentMetadata? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.thumbnail = thumbnail
        self.artwork = artwork
        self.content = content
        self.metadata = metadata
    }
}
