import Foundation
import SwiftUI
import Observation
import SonosKit


@Observable public final class Router {
    static var main = Router()
    static var search = Router()
    
    var path: [RouterDestination] = []
    var selection: RouterDestination?
    var presentedSheet: SheetDestination?
    
    @MainActor var inspectorSheet: InspectorDestination?
    @MainActor var popover: SheetDestination?
    @MainActor var volumePopover: SheetDestination?

    var dismiss: Bool = false

    private let sonosService: SonosService

    public init(sonosService: SonosService = .shared) {
        self.sonosService = sonosService
    }

    @MainActor
    func navigate(to: RouterDestination) {
        if !path.contains(to) {
            path.append(to)
        }
    }

    func sheet(to: SheetDestination?) {
        presentedSheet = to
    }
}

