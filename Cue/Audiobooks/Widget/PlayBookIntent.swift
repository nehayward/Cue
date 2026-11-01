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

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await BookShelfWidgetPublisher.shared.play(bookID: bookID)
        #endif
        return .result()
    }
}
