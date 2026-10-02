//
//  PlaybackMediaInfo.swift
//  SonosKit
//
//  Created by Nick Hayward on 6/27/25.
//

import Foundation

public struct PlaybackMediaInfo {
    let playbackService: PlaybackService?
    let artwork: URL?
    let title: String?
    /// What the transport is playing (`CurrentURI`) — for a radio station,
    /// the stream itself or the service's reference to it.
    var currentURI: String? = nil
    /// How many tracks the queue holds (`NrTracks`), whatever is playing.
    var queueTotal: Int? = nil
}
