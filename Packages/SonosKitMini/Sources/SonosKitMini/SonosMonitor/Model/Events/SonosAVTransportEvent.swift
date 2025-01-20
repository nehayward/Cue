struct SonosAVTransportEvent: Sendable {
    let isAlarmRunning: Bool
    let transportState: String?
    let currentPlayMode: String?
    let queueTotal: Int
    let currentTrackPosition: Int
    let currentTrackDuration: String?
    let currentTrackURI: String
    let currentTrackMetadata: SonosTrackMetadata?
    let musicService: SonosMusicServiceType
    let trackID: String
    let nextTrackURI: String?
    let nextTrackMetadata: SonosTrackMetadata?
    let avTransportURI: String?
    let avTransportURIMetaData: SonosTrackMetadata?
    let currentTransportActions: String?
    let currentCrossfadeMode: Bool?
    
    var groupedWithID: String? {
        currentTrackURI.components(separatedBy: ":").last
    }
}
