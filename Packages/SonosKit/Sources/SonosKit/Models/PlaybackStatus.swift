
public enum PlaybackStatus {
    case playing
    case paused
    case transitioning
    /// The speaker couldn't be asked: the request failed or the reply didn't
    /// parse. Not a state, so nothing should act on it. It used to be reported
    /// as `.transitioning`, and a failed read — common in the first moments
    /// after the app comes back — pulsed the play button, or read as "not
    /// playing" and flipped it to play until the next poll flipped it back.
    case unknown
}

extension PlaybackStatus {
    /// Whether the transport is between states, or nil when it couldn't be
    /// read — in which case whatever the room already believes should stand.
    public var isTransitioning: Bool? {
        self == .unknown ? nil : self == .transitioning
    }
}
