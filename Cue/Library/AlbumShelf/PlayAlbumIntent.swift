import AppIntents

// Shared with the widget extension, whose covers and Play buttons run it;
// not offered to Siri or Shortcuts. It's an audio playback intent, so the
// system performs it in Cue's process, launching Cue in the background if
// it isn't running: in the extension `perform` is never called, and
// compiles empty.

/// The album shelf widget's Play: plays an album, or plays or pauses the
/// one in the player.
struct PlayAlbumIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Album"
    static let description = IntentDescription("Plays an album, or pauses it.")
    static let isDiscoverable = false

    /// The album's key, as `AlbumShelfWidgetPublisher.key(for:)` makes it.
    @Parameter(title: "Album")
    var albumID: String

    init() {}

    init(albumID: String) {
        self.albumID = albumID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await AlbumShelfWidgetPublisher.shared.play(albumID: albumID)
        #endif
        return .result()
    }
}
