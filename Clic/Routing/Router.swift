import Foundation
import SwiftUI
import Observation
import SonosKit


@Observable public final class Router {
    static var main = Router()
    static var search = Router()
    
    var selectedID: String?
    var path: [RouterDestination] = []
    var presentedSheet: SheetDestination?
    
    @MainActor var inspectorSheet: InspectorDestination?
    @MainActor var popover: SheetDestination?
    @MainActor var volumePopover: SheetDestination?

    var dismiss: Bool = false

    @MainActor
    func navigate(to: RouterDestination) {
        if !path.contains(to) {
            path.append(to)
        }
    }

    func sheet(to: SheetDestination?) {
        presentedSheet = to
    }
    
    @MainActor
    func show(destination: RouterDestination) {
        Router.main.sheet(to: nil)
        
        switch destination {
            case let .player(groupID: id):
            selectedID = id
        default:
            break
        }
    }
}

