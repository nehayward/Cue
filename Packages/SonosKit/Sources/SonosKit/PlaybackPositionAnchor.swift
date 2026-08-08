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
///
/// Two readers, with opposite biases — see `resolve` and `display`.
public struct PlaybackPositionAnchor {
    /// What was last handed to the info center, and when.
    private var anchoredElapsed: TimeInterval = 0
    private var anchoredAt: Date = .distantPast
    private var anchoredWhilePlaying = false
    /// Whether `commit` has run since the last reset. Before it has there is no
    /// timeline to interpolate along, which `display` has to know about.
    private var isAnchored = false
    /// The last model position seen, to distinguish "the speaker just reported
    /// this" from "this has been frozen since the poll stopped".
    private var lastModelElapsed: TimeInterval = -1

    /// How far past the current estimate the speaker has to be before it's worth
    /// re-anchoring. Below this the interpolation is already right and a
    /// correction would only risk visible jitter.
    ///
    /// **It cannot go below one second.** `Room.playbackPosition` comes from
    /// AVTransport's `RelTime`, which Sonos formats as `h:mm:ss` — so the
    /// reading is truncated to a whole second, and a *correct* interpolation
    /// legitimately sits up to a full second above it. Tighten this and the
    /// position snaps backwards on every poll.
    private static let driftTolerance: TimeInterval = 2000

    public struct Resolution {
        /// The position to publish, in milliseconds.
        public let elapsed: TimeInterval
        /// True when the speaker reported a position far enough from what the
        /// system is showing to be worth a republish on its own.
        public let drifted: Bool
    }

    public init() {}

    /// Resolves the position to publish, for a surface that gets *written* to.
    ///
    /// - Parameters:
    ///   - modelElapsed: the speaker's reported position, in milliseconds.
    ///   - duration: track length in milliseconds; `0` for a live stream.
    ///   - now: injected so this is testable.
    public mutating func resolve(
        modelElapsed: TimeInterval,
        duration: TimeInterval,
        now: Date = .now
    ) -> Resolution {
        let modelMoved = modelElapsed != lastModelElapsed
        lastModelElapsed = modelElapsed

        let interpolated = interpolation(at: now)

        return Resolution(
            elapsed: clamped(modelMoved ? modelElapsed : interpolated, duration: duration),
            drifted: modelMoved && abs(modelElapsed - interpolated) > Self.driftTolerance
        )
    }

    /// The position to *show* right now, for a surface that redraws on its own
    /// clock instead of being written to.
    ///
    /// Same interpolation as `resolve`, opposite bias — and that difference is
    /// the whole reason this exists separately. `resolve` answers "we are about
    /// to write the info center, what number goes in it", which happens only
    /// when something real changed, so preferring the speaker's fresh reading is
    /// right there. A view redraws several times a second, and the reading is
    /// truncated to a whole second (see `driftTolerance`) — preferring it at that
    /// rate just reproduces the truncation, and the scrubber sits still and then
    /// jumps a second.
    ///
    /// So here the interpolation wins by default, and the speaker's number only
    /// intervenes once it has drifted past `driftTolerance`: a seek, a skip, or
    /// another controller moving the track.
    ///
    /// Self-committing, because for a display clock every read *is* what was
    /// shown — there is no separate "did we use it" for the caller to get wrong.
    public mutating func display(
        modelElapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        now: Date = .now
    ) -> TimeInterval {
        let modelMoved = modelElapsed != lastModelElapsed
        lastModelElapsed = modelElapsed

        let elapsed: TimeInterval
        if isAnchored {
            let interpolated = interpolation(at: now)
            let drifted = modelMoved && abs(modelElapsed - interpolated) > Self.driftTolerance
            elapsed = drifted ? modelElapsed : interpolated
        } else {
            // A first read, or the first after a track change: there is no
            // timeline yet, so the speaker's number is all there is. Falling
            // through to the interpolation here would anchor at zero and leave
            // the whole track a second short.
            elapsed = modelElapsed
        }

        let shown = clamped(elapsed, duration: duration)
        commit(elapsed: shown, isPlaying: isPlaying, at: now)
        return shown
    }

    /// Records what was actually published, so the next interpolation runs from
    /// there. Only call this when the info center really was written.
    public mutating func commit(elapsed: TimeInterval, isPlaying: Bool, at now: Date = .now) {
        anchoredElapsed = elapsed
        anchoredAt = now
        anchoredWhilePlaying = isPlaying
        isAnchored = true
    }

    /// Where the anchor says we are now. A paused anchor doesn't move.
    private func interpolation(at now: Date) -> TimeInterval {
        anchoredWhilePlaying
            ? anchoredElapsed + now.timeIntervalSince(anchoredAt) * 1000
            : anchoredElapsed
    }

    /// Nothing may go negative, and nothing may run past the end of a track that
    /// has one — a live stream has no end to run past.
    private func clamped(_ elapsed: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let floored = max(elapsed, 0)
        return duration > 0 ? min(floored, duration) : floored
    }

    /// Forgets everything — a new track, a new speaker, a new session. The next
    /// resolve takes the speaker's number.
    public mutating func reset() {
        self = PlaybackPositionAnchor()
    }
}
