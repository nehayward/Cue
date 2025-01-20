//
//  Metadata.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/20/24.
//

import Foundation

public extension SonosTrack {
    struct Metadata: Sendable, Hashable {
        public let ISRC: String?
        public let openInURL: URL?
        public let contentType: ContentType?
        public var stationID: String?
        public var stationName: String?
        public let song: String?
        public let album: String?
        public let artist: String?
        
        init(
            ISRC: String?,
            openInURL: URL?,
            contentType: ContentType?,
            stationID: String? = nil,
            stationName: String? = nil,
            song: String? = nil,
            album: String? = nil,
            artist: String? = nil
        ) {
            self.ISRC = ISRC
            self.openInURL = openInURL
            self.contentType = contentType
            self.stationID = stationID
            self.stationName = stationName
            self.song = song
            self.album = album
            self.artist = artist
        }
    }
}
