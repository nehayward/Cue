import AppIntents

enum ToggleOption: String, AppEnum, CaseIterable, Equatable  {
    case turn
    case toggle
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Toggle Option")
    }
    
    static var caseDisplayRepresentations: [ToggleOption : DisplayRepresentation] {
        [.turn: DisplayRepresentation(stringLiteral: "Turn"),
         .toggle: DisplayRepresentation(stringLiteral: "Toggle")]
    }
}
