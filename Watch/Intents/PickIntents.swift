import AppIntents
import WatchSync

/// An album, playlist, artist or song on the watch, for Siri and Shortcuts
/// to name.
struct PickEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Music on Apple Watch"
    static let defaultQuery = PickQuery()

    /// The pick's key (`WatchPick.key`).
    let id: String
    let title: String
    let subtitle: String

    init(_ pick: WatchPick) {
        id = pick.key
        title = pick.title
        subtitle = pick.subtitle
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.isEmpty ? nil : "\(subtitle)")
    }
}

struct PickQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PickEntity] {
        let picks = WatchDownloadStore.shared.picks
        return identifiers.compactMap { picks.pick(key: $0).map(PickEntity.init) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PickEntity] {
        WatchDownloadStore.shared.picks.items.map(PickEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [PickEntity] {
        WatchDownloadStore.shared.picks.items
            .filter { $0.title.localizedCaseInsensitiveContains(string) || $0.subtitle.localizedCaseInsensitiveContains(string) }
            .map(PickEntity.init)
    }
}

/// Plays one album, playlist, artist or song that's on the watch.
struct PlayPickIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play from Apple Watch"
    static let description = IntentDescription("Plays an album, playlist, artist or song that's on your Apple Watch.")

    @Parameter(title: "Music")
    var pick: PickEntity

    @Parameter(title: "Shuffle", default: false)
    var shuffle: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$pick)") {
            \.$shuffle
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try PlaybackIntentError.check(WatchPlayer.shared.play(pickKey: pick.id, shuffled: shuffle))
        return .result()
    }
}

/// What Siri and the Shortcuts app offer without setting anything up.
struct CueShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShuffleDownloadsIntent(),
            phrases: [
                "Shuffle my downloads in \(.applicationName)",
                "Shuffle \(.applicationName)",
            ],
            shortTitle: "Shuffle Downloads",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: PlayDownloadsIntent(),
            phrases: [
                "Play my downloads in \(.applicationName)",
                "Play \(.applicationName)",
            ],
            shortTitle: "Play Downloads",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PlayPickIntent(),
            phrases: [
                "Play \(\.$pick) in \(.applicationName)",
            ],
            shortTitle: "Play from Watch",
            systemImageName: "music.note.list"
        )
    }
}
