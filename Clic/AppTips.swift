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
            Text("Content playback requires authorization in the Sonos app. Go to Preferences in Clic to customize what services are shown.")
        case .libraryMediaService:
            Text("Content playback requires authorization in the Sonos app. Go to Preferences in Clic to customize what services are shown.")
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
