import AppIntents

enum PlaybackOption: String, AppEnum, CaseIterable, Equatable  {
    case play
    case pause
    case toggle
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Playback Options")
    }
    
    static var caseDisplayRepresentations: [PlaybackOption : DisplayRepresentation] {
        [.play: DisplayRepresentation(stringLiteral: "Play"),
         .pause: DisplayRepresentation(stringLiteral: "Pause"),
         .toggle: DisplayRepresentation(stringLiteral: "Toggle"),
        ]
    }
}
