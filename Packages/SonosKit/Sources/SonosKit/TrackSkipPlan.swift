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
struct TrackSkipPlan {
    enum Direction {
        case next
        case previous
    }

    enum Mode {
        /// The Sonos queue, played in order. A press moves an absolute queue
        /// position the speaker can be sent straight to.
        case queue(wrapsAround: Bool)
        /// Shuffle, or a source with no local queue (Spotify Connect, cloud
        /// queues). Only the speaker knows what comes next, so presses stay
        /// relative skips and go out one at a time.
        case relative
    }

    enum Command: Equatable {
        /// Jump to a 1-based queue position.
        case jump(to: Int)
        /// One relative skip.
        case step(forward: Bool)
        /// Back to the start of the current song.
        case restart
    }

    /// How far into a song (ms) previous restarts it rather than going back.
    static let restartThreshold: TimeInterval = 3000

    let mode: Mode
    /// Queue position of the song playing when the first press landed.
    let startPosition: Int
    /// Where the presses add up to. In relative mode the positions are only a
    /// count from `startPosition`: nothing is clamped, and nothing but the
    /// difference is sent.
    private(set) var target: Int
    /// Where the speaker was last sent — where it started, until then.
    private(set) var speakerTarget: Int
    /// A previous press asked for the current song to start over.
    private(set) var restartPending = false
    /// Commands the speaker has accepted.
    private(set) var commandsSent = 0

    init(mode: Mode, startPosition: Int) {
        self.mode = mode
        self.startPosition = startPosition
        self.target = startPosition
        self.speakerTarget = startPosition
    }

    /// How far the presses lead from the song the first press left.
    var netSteps: Int { target - startPosition }

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
    mutating func press(_ direction: Direction, playbackPosition: TimeInterval, queueTotal: Int) -> Bool {
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
            target += delta
        }
        return true
    }

    /// What to send the speaker next, or `nil` once it has everything.
    var nextCommand: Command? {
        switch mode {
        case .queue:
            if target != speakerTarget { return .jump(to: target) }
            return restartPending ? .restart : nil
        case .relative:
            // The restart can only have come from the first press — every press
            // zeroes the position — so it goes out ahead of any skips.
            if restartPending { return .restart }
            if target != speakerTarget { return .step(forward: target > speakerTarget) }
            return nil
        }
    }

    /// Records that the speaker accepted `command`.
    mutating func didSend(_ command: Command) {
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
            speakerTarget += forward ? 1 : -1
        }
    }

    /// Whether a song the speaker reported, read after everything was sent,
    /// shows the presses have landed.
    ///
    /// - Parameters:
    ///   - position: The reported song's queue position.
    ///   - isStartTrack: Whether it is the song the first press left.
    func isConfirmed(position: Int, isStartTrack: Bool) -> Bool {
        switch mode {
        case .queue:
            return position == target
        case .relative:
            // Skips that cancelled out (or a lone restart) leave the speaker on
            // the song it started on, so any fresh read is the answer.
            // Otherwise wait for it to have moved off that song.
            return speakerTarget == startPosition || !isStartTrack
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
