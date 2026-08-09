import Foundation

/// Why a speech-enhancement change didn't happen. The two cases are worth keeping
/// apart: telling someone their soundbar doesn't support a feature it does support
/// sends them looking for the wrong fix.
public enum SpeechEnhancementError: Error, Equatable {
    /// The speaker never answered — a dropped request, a stale IP, a speaker that's
    /// off the network. Says nothing about whether the feature is supported.
    case unreachable
    /// The speaker answered and has no speech-enhancement EQ at all (it isn't a
    /// soundbar).
    case unsupported
}
