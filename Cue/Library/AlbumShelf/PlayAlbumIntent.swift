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

    /// Runs in the background, as an audio intent does, and comes to the
    /// front only to ask where to play (`WidgetPlayChoice`).
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        // Not the intent's own task: one the system gives up on while the
        // listener chooses where to play would cancel the Play's requests.
        let bringForward = self.bringForward
        await Task { @MainActor in
            await AlbumShelfWidgetPublisher.shared.play(albumID: albumID, bringForward: bringForward)
        }.value
        #endif
        return .result()
    }

    #if !WIDGET_EXTENSION
    /// Brings Cue to the front from a widget's tap, where iOS lets it
    /// (iOS 26), so it can ask where to play: true once it's there.
    @MainActor
    private func bringForward() async -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            let mode = systemContext.currentMode
            if mode == .foreground { return true }
            guard mode.canContinueInForeground else { return false }
            do {
                try await continueInForeground("Choose where this album plays in Cue.", alwaysConfirm: false)
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }
    #endif
}
