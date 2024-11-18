import AppIntents

enum ControlOption: String, AppEnum, CaseIterable, Equatable  {
    case start
    case stop
    case toggle
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Control Option")
    }
    
    static var caseDisplayRepresentations: [ControlOption : DisplayRepresentation] {
        [.start: DisplayRepresentation(stringLiteral: "Start"),
         .stop: DisplayRepresentation(stringLiteral: "Stop"),
         .toggle: DisplayRepresentation(stringLiteral: "Toggle")]
    }
    
}
