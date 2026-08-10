import Foundation

/// Decides what elapsed time to hand a system media surface — the Now Playing
/// info center, a Live Activity — and whether it's worth handing it anything.
///
/// A value type on purpose. This is the subtlest logic in the Now Playing
/// feature — it caused two separate visible bugs — and as a method on a
/// `@MainActor` singleton full of `AVAudioSession` and `MPRemoteCommandCenter`
/// calls it was unreachable from a test. Here it's pure: give it numbers, get
/// numbers back. See `PlaybackPositionAnchorTests`.
///
/// The problem it solves: these surfaces do not need a position ticked at them.
/// Given an anchor and a playback rate they interpolate elapsed time on their
/// own, so the anchor only needs re-stating when it would actually be wrong.
/// Meanwhile `Room.playbackPosition` — the speaker's reported position — only
/// advances when something writes it, and in the background the only writer is
/// a socket event. So the model sits frozen between events while the system's
/// interpolation keeps moving, correctly.
///
/// That asymmetry is what makes the naive versions wrong:
///
/// - Re-anchoring whenever the model and the interpolation disagree drags the
///   scrubber back to the frozen value every time, which reads as playback
///   having stopped.
/// - Publishing the model's position on any state change (a pause changes state,
///   so it always publishes) snaps the scrubber back to wherever the last
///   `playbackStatus` happened to land — often the start of the track.
///
/// So: the speaker's number is authoritative only when it has just moved.
/// Otherwise carry the interpolation forward.
public struct PlaybackPositionAnchor {
    /// What was last handed to the info center, and when.
    private var anchoredElapsed: TimeInterval = 0
    private var anchoredAt: Date = .distantPast
    private var anchoredWhilePlaying = false
    /// The last model position seen, to distinguish "the speaker just reported
    /// this" from "this has been frozen since the poll stopped".
    private var lastModelElapsed: TimeInterval = -1

    /// How far past the system's own estimate the speaker has to be before it's
    /// worth re-anchoring. Below this the interpolation is already right and a
    /// republish would only risk visible jitter.
    private static let driftTolerance: TimeInterval = 2000

    public struct Resolution {
        /// The position to publish, in milliseconds.
        public let elapsed: TimeInterval
        /// True when the speaker reported a position far enough from what the
        /// system is showing to be worth a republish on its own.
        public let drifted: Bool
    }

    /// Resolves the position to publish.
    ///
    /// - Parameters:
    ///   - modelElapsed: the speaker's reported position, in milliseconds.
    ///   - duration: track length in milliseconds; `0` for a live stream.
    ///   - now: injected so this is testable.
    public init() {}

    public mutating func resolve(
        modelElapsed: TimeInterval,
        duration: TimeInterval,
        now: Date = .now
    ) -> Resolution {
        let modelMoved = modelElapsed != lastModelElapsed
        lastModelElapsed = modelElapsed

        let interpolated = anchoredWhilePlaying
            ? anchoredElapsed + now.timeIntervalSince(anchoredAt) * 1000
            : anchoredElapsed

        var elapsed = max(modelMoved ? modelElapsed : interpolated, 0)
        if duration > 0 { elapsed = min(elapsed, duration) }

        return Resolution(
            elapsed: elapsed,
            drifted: modelMoved && abs(modelElapsed - interpolated) > Self.driftTolerance
        )
    }

    /// Records what was actually published, so the next interpolation runs from
    /// there. Only call this when the info center really was written.
    public mutating func commit(elapsed: TimeInterval, isPlaying: Bool, at now: Date = .now) {
        anchoredElapsed = elapsed
        anchoredAt = now
        anchoredWhilePlaying = isPlaying
    }

    /// Forgets everything — a new track, a new speaker, a new session. The next
    /// resolve takes the speaker's number.
    public mutating func reset() {
        self = PlaybackPositionAnchor()
    }
}
