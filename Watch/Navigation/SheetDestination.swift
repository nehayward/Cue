import SonosKit
import SwiftUI

enum SheetDestination: Identifiable {
    case preferences
    case scenes

    var id: String {
        switch self {
        case .preferences:
            "preferences"
        case .scenes:
            "scenes"
        }
    }
}
