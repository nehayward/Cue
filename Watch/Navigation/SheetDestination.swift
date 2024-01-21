import SonosKit
import SwiftUI

enum SheetDestination: Identifiable {
    case preferences

    var id: String {
        switch self {
        case .preferences:
            "preferences"
        }
    }
}
