import AppIntents

enum SpeechLevelOption: Int, AppEnum, CaseIterable {
    case off = 0
    case low = 1
    case medium = 2
    case high = 3
    case max = 4

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Speech Level")
    }

    static var caseDisplayRepresentations: [SpeechLevelOption: DisplayRepresentation] {
        [
            .off: "Off",
            .low: "Low",
            .medium: "Medium",
            .high: "High",
            .max: "Max",
        ]
    }
}
