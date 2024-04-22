import Observation

@Observable
final class Router {
    static var main = Router()
    var path: [Path] = []
    var presentedSheet: SheetDestination?
    var dismiss: Bool = false
    var selectedID: String?

    @MainActor
    func sheet(to: SheetDestination?) {
        presentedSheet = to
    }
}
