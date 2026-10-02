import Foundation

/// Decides when a play counts as a listen, by the rule Last.fm set and
/// most servers follow: a song of at least 30 seconds counts once half of
/// it, or four minutes, has actually been heard — whichever comes first.
///
/// Fed the player's position as it plays. Only time that passes in
/// ordinary steps adds up: a seek forward isn't listening, and a seek back
/// doesn't take away what was heard.
public struct ListenTracker: Sendable, Equatable {
    /// Shorter songs never count.
    public static let minimumDuration: TimeInterval = 30
    /// The most a long song needs heard.
    public static let maximumThreshold: TimeInterval = 240
    /// The largest step between two readings taken as playback rather than
    /// a seek. Well above the player's half-second poll, so a poll that
    /// runs late in the background still counts.
    public static let maximumStep: TimeInterval = 5

    /// The song's length; zero while it isn't known.
    public var duration: TimeInterval
    /// Seconds actually heard so far.
    public private(set) var listened: TimeInterval = 0
    /// Whether the play has counted. It counts once.
    public private(set) var hasCounted = false
    private var lastPosition: TimeInterval?

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    /// How much has to be heard for the play to count, or nil for a song
    /// too short to count, or one whose length isn't known yet.
    public var threshold: TimeInterval? {
        guard duration >= Self.minimumDuration else { return nil }
        return min(duration / 2, Self.maximumThreshold)
    }

    /// Notes the position while playing. True exactly once: the reading
    /// that takes the play over the threshold.
    public mutating func advance(to position: TimeInterval) -> Bool {
        defer { lastPosition = position }
        if let lastPosition {
            let step = position - lastPosition
            if step > 0, step <= Self.maximumStep {
                listened += step
            }
        }
        guard !hasCounted, let threshold, listened >= threshold else { return false }
        hasCounted = true
        return true
    }

    /// Playback stopped advancing: the next reading starts a fresh step, so
    /// a seek made while paused isn't taken for listening.
    public mutating func pause() {
        lastPosition = nil
    }
}
