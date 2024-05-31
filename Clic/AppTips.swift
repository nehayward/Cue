import SwiftUI
import TipKit

enum AppTip: Tip {
    case mediaService

    var title: Text {
        switch self {
        case .mediaService:
            Text("Change Search")
        }
    }

    var message: Text? {
        switch self {
        case .mediaService:
            Text("Must be authorized in Sonos app to play content.")
        }
    }
    
//    var image: Image? {
//        switch self {
//        case .mediaService: Image(systemName: "plus")
//        }
//    }
//
//    var actions: [Action] {
//        switch self {
//        case .mediaService: [Action(id: "add", title: "Add")]
//        }
//    }
}
