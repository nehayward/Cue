public enum SonosPlaybackStatus {
    case playing
    case paused
    case transitioning
    
    var isPlaying: Bool {
        [.playing, .transitioning].contains(self)
    }
}
