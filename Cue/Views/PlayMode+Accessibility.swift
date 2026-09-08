import SonosKit

extension PlayMode {
    /// What VoiceOver reads for the play-mode badge on a queue button, and
    /// as the value of the shuffle and repeat toggles.
    var accessibilityDescription: String {
        if contains(.shuffle) { return "Shuffle on" }
        if contains(.repeatOne) { return "Repeat one" }
        if isRepeatEnabled { return "Repeat all" }
        return "Repeat off"
    }

    var repeatAccessibilityValue: String {
        if contains(.repeatOne) { return "One" }
        if isRepeatEnabled { return "All" }
        return "Off"
    }
}
