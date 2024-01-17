import Foundation
import SwiftUI
import Observation
import SonosKit


@Observable public final class Router {
    var path: [RouterDestination] = []
    @MainActor var presentedSheet: SheetDestination?
    var dismiss: Bool = false

    private let sonosService: SonosService

    public init(sonosService: SonosService = .shared) {
        self.sonosService = sonosService
    }

    @MainActor
    func navigate(to: RouterDestination) {
        path.append(to)
    }

    @MainActor
    func sheet(to: SheetDestination?) {
        presentedSheet = to
    }
}

