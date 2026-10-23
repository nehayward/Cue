import AppIntents

// Shared with the widget extension (its Smart Stack button and its Control
// Center control run this); not offered to Siri or Shortcuts. It's an audio
// playback intent, so the system performs it in the watch app's process,
// which the widget extension can't play from: there `perform` is never
// called, and compiles empty.

/// Shuffles everything on the watch.
struct ShuffleDownloadsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle Downloads"
    static let description = IntentDescription("Shuffles the music downloaded to this watch.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try PlaybackIntentError.check(WatchPlayer.shared.playDownloads(shuffled: true))
        #endif
        return .result()
    }
}

enum PlaybackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingDownloaded

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingDownloaded: "Nothing is downloaded to this watch yet."
        }
    }

    /// Throws when playback didn't start: nothing to play was here.
    static func check(_ started: Bool) throws {
        if !started { throw nothingDownloaded }
    }
}
