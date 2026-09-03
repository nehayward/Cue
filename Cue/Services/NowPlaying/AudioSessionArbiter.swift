import Foundation

/// Decides what happens to the shared `AVAudioSession` when a transient user of
/// it finishes.
///
/// Cue has more than one claimant: song previews (`AudioPlaybackService`) take
/// the session for thirty seconds, while a long-lived holder may be sitting
/// behind them — today that's the Lock Screen Now Playing session, which keeps a
/// silent `.playback` session alive to own the system Now Playing card.
///
/// Without an arbiter the transient user has to know about the long-lived one:
/// "am I allowed to deactivate, or is someone else holding this?" That check
/// used to live in `AudioPlaybackService`, naming `NowPlayingSessionService`
/// directly — a shared service depending on a specific feature, which then
/// couldn't be deleted without editing it.
///
/// Here the dependency points the other way. The holder registers a claim; the
/// transient user asks the arbiter, which knows nothing about either. With no
/// claim registered — the feature off, or deleted outright — `handBack()`
/// returns false and the ordinary deactivate runs, which is exactly the
/// behaviour that existed before any of this.
@MainActor
final class AudioSessionArbiter {
    static let shared = AudioSessionArbiter()

    private var reclaim: (() -> Void)?

    private init() {}

    var isClaimed: Bool { reclaim != nil }

    /// Registers a long-lived holder. `reclaim` is invoked when a transient user
    /// is about to give the session up, and should re-establish whatever
    /// category and playback the holder needs.
    func claim(reclaim: @escaping () -> Void) {
        self.reclaim = reclaim
    }

    func resign() {
        reclaim = nil
    }

    /// Hands the session back to the registered holder.
    ///
    /// Returns `true` when a holder took it, meaning the caller must *not*
    /// deactivate — deactivating and letting the holder re-activate would drop
    /// its claim on the Now Playing card for the gap in between.
    func handBack() -> Bool {
        guard let reclaim else { return false }
        reclaim()
        return true
    }
}
