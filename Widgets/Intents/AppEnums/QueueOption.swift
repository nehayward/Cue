import AppIntents
import SonosKit

/// Shortcuts-facing choice of where to place content in the Sonos queue.
/// Maps onto `SonosKit.QueuePosition`.
enum QueueOption: String, AppEnum, CaseIterable, Equatable {
    case automatic
    case playNow
    case playNext
    case playLast
    case replaceQueue

    /// `.automatic` returns nil so the intent can pick a position based on
    /// content type, matching the Play on Cue share sheet.
    var queuePosition: QueuePosition? {
        switch self {
        case .automatic: nil
        case .playNow: .now
        case .playNext: .next
        case .playLast: .end
        case .replaceQueue: .replace
        }
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Add to Queue")
    }

    static var caseDisplayRepresentations: [QueueOption: DisplayRepresentation] {
        [
            .automatic: DisplayRepresentation(
                title: "Automatic",
                image: .init(systemName: "sparkles")
            ),
            .playNow: DisplayRepresentation(
                title: "Play Now",
                image: .init(systemName: "play.fill")
            ),
            .playNext: DisplayRepresentation(
                title: "Play Next",
                image: .init(systemName: "text.insert")
            ),
            .playLast: DisplayRepresentation(
                title: "Play Last",
                image: .init(systemName: "text.append")
            ),
            .replaceQueue: DisplayRepresentation(
                title: "Replace Queue",
                image: .init(systemName: "arrow.triangle.2.circlepath")
            )
        ]
    }

    var displayRepresentation: DisplayRepresentation {
        QueueOption.caseDisplayRepresentations[self]!
    }

    static var defaultQuery = allCases
}
