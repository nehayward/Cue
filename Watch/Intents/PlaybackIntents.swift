import AppIntents

// Shared with the widget extension (its Smart Stack button and its Control
// Center control run these). They're audio playback intents, so the system
// performs them in the watch app's process, which the widget extension
// can't play from: there `perform` is never called, and compiles empty.

/// Shuffles everything on the watch.
struct ShuffleDownloadsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle Downloads"
    static let description = IntentDescription("Shuffles the music on your Apple Watch.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try PlaybackIntentError.check(WatchPlayer.shared.playDownloads(shuffled: true))
        #endif
        return .result()
    }
}

/// Plays everything on the watch, in order.
struct PlayDownloadsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Downloads"
    static let description = IntentDescription("Plays the music on your Apple Watch, in order.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try PlaybackIntentError.check(WatchPlayer.shared.playDownloads(shuffled: false))
        #endif
        return .result()
    }
}

enum PlaybackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingDownloaded

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingDownloaded: "None of that is on your Apple Watch yet."
        }
    }

    /// Throws when playback didn't start: nothing to play was here.
    static func check(_ started: Bool) throws {
        if !started { throw nothingDownloaded }
    }
}
