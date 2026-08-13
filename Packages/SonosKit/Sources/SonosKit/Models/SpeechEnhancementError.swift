import Foundation

/// Why a speech-enhancement change didn't happen. Worth keeping apart: telling
/// someone their soundbar doesn't support a feature it does support sends them
/// looking for the wrong fix.
public enum SpeechEnhancementError: Error, Equatable {
    /// The speaker never answered. Says nothing about whether it's supported.
    case unreachable
    /// The speaker answered and has no speech-enhancement EQ (it isn't a soundbar).
    case unsupported
}
