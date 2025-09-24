import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleClicMini = Self("toggleClicMini", default: .init(.c, modifiers: [.command, .control]))
    static let volumeUp = Self("volumeUp", default: .init(.upArrow, modifiers: [.command, .control]))
    static let volumeDown = Self("volumeDown", default: .init(.downArrow, modifiers: [.command, .control]))
    static let nextTrack = Self("nextTrack", default: .init(.rightArrow, modifiers: [.command, .control]))
    static let previousTrack = Self("previousTrack", default: .init(.leftArrow, modifiers: [.command, .control]))
}
