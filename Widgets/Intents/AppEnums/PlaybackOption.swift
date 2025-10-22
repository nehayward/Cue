import AppIntents

enum PlaybackOption: String, AppEnum, CaseIterable, Equatable {
    case play
    case pause
    case toggle
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Playback Options")
    }
    
    static var caseDisplayRepresentations: [PlaybackOption: DisplayRepresentation] {
        [
            .play: DisplayRepresentation(
                title: "Play",
                image: .init(systemName: "play.fill")
            ),
            .pause: DisplayRepresentation(
                title: "Pause",
                image: .init(systemName: "pause.fill")
            ),
            .toggle: DisplayRepresentation(
                title: "Toggle",
                image: .init(systemName: "playpause.fill")
            )
        ]
    }
    
    var displayRepresentation: DisplayRepresentation {
        PlaybackOption.caseDisplayRepresentations[self]!
    }
    
    static var defaultQuery = allCases
}
