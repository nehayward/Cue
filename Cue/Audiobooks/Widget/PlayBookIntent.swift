import AppIntents

// Shared with the widget extension, whose covers and Play buttons run it;
// not offered to Siri or Shortcuts. It's an audio playback intent, so the
// system performs it in Cue's process, launching Cue in the background if
// it isn't running: in the extension `perform` is never called, and
// compiles empty.

/// The book shelf widget's Play: plays a book from where it was left, or
/// pauses it while it plays.
struct PlayBookIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Book"
    static let description = IntentDescription("Plays a book from where you left it, or pauses it.")
    static let isDiscoverable = false

    /// The book's key, as `AudiobookProgressStore` keys it.
    @Parameter(title: "Book")
    var bookID: String

    init() {}

    init(bookID: String) {
        self.bookID = bookID
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
            await BookShelfWidgetPublisher.shared.play(bookID: bookID, bringForward: bringForward)
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
                try await continueInForeground("Choose where this book plays in Cue.", alwaysConfirm: false)
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
