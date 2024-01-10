import SonosKit
import SwiftUI

enum SheetDestination: Identifiable {
    case settings
    case paywall
    case groupScreen(groupScreenViewModel: GroupScreenViewModel, group: GroupRoom)
    case search(group: GroupRoom)

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .paywall:
            "paywall"
        case .groupScreen:
            "groupScreen"
        case .search:
            "search"
        }
    }
}
