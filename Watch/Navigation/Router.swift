import Observation

@Observable
final class Router {
    var paths: [Path] = []
    var presentedSheet: SheetDestination?
    var dismiss: Bool = false

    @MainActor
    func sheet(to: SheetDestination?) {
        presentedSheet = to
    }
}
