import AppIntents
import SonosKit

enum Launcher: String, AppEnum, CaseIterable, Equatable  {
    case room
    case alarms
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Toggle Option")
    }
    
    static var caseDisplayRepresentations: [Launcher : DisplayRepresentation] {
        [.room: DisplayRepresentation(stringLiteral: "Turn"),
         .alarms: DisplayRepresentation(stringLiteral: "Toggle")]
    }
    
}
