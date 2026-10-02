import Foundation

/// The arithmetic of a run of skip presses: where they add up to, and what the
/// speaker has to be sent next to get there.
///
/// A value type, kept apart from the timing and networking in
/// `SonosService+TrackSkip.swift` so it can be tested on its own — see
/// `TrackSkipPlanTests`.
///
/// The point of it is that a press doesn't send anything. It moves a target,
/// and a single sender chases that target. For a queue played in order the
/// target is an absolute queue position, so however many presses land while a
/// command is in flight, catching up costs one `Seek` — not one skip per press,
/// each of which the speaker would otherwise open a stream for in turn.
public struct TrackSkipPlan: Equatable, Sendable {
    public enum Direction: Sendable {
        case next
        case previous
    }

    public enum Mode: Equatable, Sendable {
        /// The Sonos queue, played in order. A press moves an absolute queue
        /// position the speaker can be sent straight to.
        case queue(wrapsAround: Bool)
        /// Shuffle, or a source with no local queue (Spotify Connect, cloud
        /// queues). Only the speaker knows what comes next, so presses stay
        /// relative skips and go out one at a time.
        case relative
    }

    public enum Command: Equatable, Sendable {
        /// Jump to a 1-based queue position.
        case jump(to: Int)
        /// One relative skip.
        case step(forward: Bool)
        /// Back to the start of the current song.
        case restart
    }

    /// How far into a song (ms) previous restarts it rather than going back.
    public static let restartThreshold: TimeInterval = 3000

    public let mode: Mode
    /// Queue position of the song playing when the first press landed.
    public let startPosition: Int
    /// Queue mode: the position the presses add up to.
    public private(set) var target: Int
    /// Queue mode: the position the speaker was last sent to — where it
    /// started, until something has been sent.
    public private(set) var speakerTarget: Int
    /// Relative mode: skips pressed but not yet sent. Negative is backwards.
    public private(set) var pendingSteps = 0
    /// Relative mode: net skips sent so far. Negative is backwards.
    public private(set) var sentSteps = 0
    /// A previous press asked for the current song to start over.
    public private(set) var restartPending = false
    /// Commands the speaker has accepted.
    public private(set) var commandsSent = 0

    public init(mode: Mode, startPosition: Int) {
        self.mode = mode
        self.startPosition = startPosition
        self.target = startPosition
        self.speakerTarget = startPosition
    }

    /// Relative mode: where the presses add up to, counted from the song the
    /// first press left.
    public var netSteps: Int { sentSteps + pendingSteps }

    /// Records a press.
    ///
    /// - Parameters:
    ///   - playbackPosition: How far into the song the player is showing, in
    ///     milliseconds. Past `restartThreshold`, previous restarts the song.
    ///     Every press puts the player back at zero, so pressing previous twice
    ///     restarts the song and then goes back one, as on any player.
    ///   - queueTotal: The queue's length, or `0` when it isn't known yet.
    /// - Returns: `false` when the press goes nowhere — next on the last song
    ///   of a queue that doesn't repeat.
    @discardableResult
    public mutating func press(_ direction: Direction, playbackPosition: TimeInterval, queueTotal: Int) -> Bool {
        if direction == .previous, playbackPosition >= Self.restartThreshold {
            restartPending = true
            return true
        }

        let delta = direction == .next ? 1 : -1
        switch mode {
        case .queue(let wrapsAround):
            let moved = Self.clamp(target + delta, queueTotal: queueTotal, wrapsAround: wrapsAround)
            guard moved != target else {
                // Previous on the first song has nowhere to go back to; starting
                // it over is the nearest thing.
                if direction == .previous {
                    restartPending = true
                    return true
                }
                return false
            }
            target = moved
        case .relative:
            pendingSteps += delta
        }
        return true
    }

    /// What to send the speaker next, or `nil` once it has everything.
    public var nextCommand: Command? {
        switch mode {
        case .queue:
            if target != speakerTarget { return .jump(to: target) }
            return restartPending ? .restart : nil
        case .relative:
            // The restart can only have come from the first press — every press
            // zeroes the position — so it goes out ahead of any skips.
            if restartPending { return .restart }
            if pendingSteps != 0 { return .step(forward: pendingSteps > 0) }
            return nil
        }
    }

    /// Records that the speaker accepted `command`.
    public mutating func didSend(_ command: Command) {
        commandsSent += 1
        switch command {
        case .jump(let position):
            speakerTarget = position
            // A jump starts the song from the top, so a restart waiting behind
            // it is already done.
            restartPending = false
        case .restart:
            restartPending = false
        case .step(let forward):
            let delta = forward ? 1 : -1
            pendingSteps -= delta
            sentSteps += delta
        }
    }

    /// Whether a song the speaker reported, read after everything was sent,
    /// shows the presses have landed.
    ///
    /// - Parameters:
    ///   - position: The reported song's queue position.
    ///   - isStartTrack: Whether it is the song the first press left.
    public func isConfirmed(position: Int, isStartTrack: Bool) -> Bool {
        switch mode {
        case .queue:
            return position == target
        case .relative:
            // Skips that cancelled out (or a lone restart) leave the speaker on
            // the song it started on, so any fresh read is the answer.
            // Otherwise wait for it to have moved off that song.
            return sentSteps == 0 || !isStartTrack
        }
    }

    static func clamp(_ position: Int, queueTotal: Int, wrapsAround: Bool) -> Int {
        if position < 1 {
            return wrapsAround && queueTotal > 0 ? queueTotal : 1
        }
        // An unknown length can't be clamped against. A jump past the end is
        // refused by the speaker, which the sender treats as the end of the run.
        if queueTotal > 0, position > queueTotal {
            return wrapsAround ? 1 : queueTotal
        }
        return position
    }
}
