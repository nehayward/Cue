//
//  TrackMetaData.swift
//  Listener
//
//  Created by Nick Hayward on 1/7/25.
//

public struct SonosTrackMetadata: Hashable, Equatable {
    public let title: String
    public let creator: String
    public let album: String
    public let albumArtURI: String?
    public let streamInfo: SonosAudioStreamInfo?
}
