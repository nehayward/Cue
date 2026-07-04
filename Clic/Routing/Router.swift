import Foundation
import SwiftUI
import Observation
import SonosKit


@Observable public final class Router {
    static var main = Router()
    static var search = Router()
    static var secondary = Router()
    static var browse = Router()

    var selectedID: String?
    var path: [RouterDestination] = []
    var presentedSheet: SheetDestination?
    /// Destinations presented as `fullScreenCover` rather than `.sheet`.
    /// Currently used for `.paywall` and `.onboard` — moments where we want
    /// full canvas and no swipe-to-dismiss. Use `fullScreenCover(to:)` to
    /// route, rather than `sheet(to:)`, so intent reads at the call site.
    var presentedFullScreenCover: SheetDestination?
    var secondarySheet: SheetDestination?

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

    @MainActor private static var lastInspectorToggle: ContinuousClock.Instant?

    /// Toggles an inspector destination on or off, deduplicating immediate
    /// repeats: Catalyst can deliver a bare-key menu shortcut (S/B/Q) twice
    /// for a single press, which made the toggle open the inspector and
    /// instantly close it again.
    @MainActor
    func toggleInspector(_ destination: InspectorDestination) {
        let now = ContinuousClock.now
        if let last = Self.lastInspectorToggle, now - last < .milliseconds(250) {
            return
        }
        Self.lastInspectorToggle = now

        if inspectorSheet != destination {
            inspectorSheet = destination
        } else {
            inspectorSheet = nil
        }
    }

    func sheet(to: SheetDestination?) {
        presentedSheet = to
    }

    /// Counterpart to `sheet(to:)` for destinations that should present as a
    /// fullScreenCover rather than a sheet (paywall, onboarding).
    func fullScreenCover(to: SheetDestination?) {
        presentedFullScreenCover = to
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

