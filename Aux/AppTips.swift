import SwiftUI
import TipKit

@MainActor
enum AppTip: Tip {
    case mediaService
    case libraryMediaService

    var title: Text {
        switch self {
        case .mediaService:
            Text("Change Search")
        case .libraryMediaService:
            Text("Change Service")
        }
    }

    var message: Text? {
        switch self {
        case .mediaService:
            Text("Authorize services in the Sonos app to play them here.")
        case .libraryMediaService:
            Text("Authorize services in the Sonos app to play them here.")
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
