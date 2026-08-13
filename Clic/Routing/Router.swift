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

    @MainActor
    private static var lastInspectorToggle: (destination: InspectorDestination, at: ContinuousClock.Instant)?

    /// Toggles an inspector destination on or off, deduplicating immediate
    /// repeats: Catalyst can deliver a bare-key menu shortcut (S/B/Q) twice
    /// for a single press, which made the toggle open the inspector and
    /// instantly close it again.
    ///
    /// The window is keyed by destination, so a duplicate press of the *same*
    /// button (open or close) is dropped, while switching to a *different*
    /// inspector — Search → Browse → Queue in quick succession — goes through
    /// immediately instead of being swallowed by a shared cooldown.
    @MainActor
    func toggleInspector(_ destination: InspectorDestination) {
        let now = ContinuousClock.now
        if let last = Self.lastInspectorToggle,
           last.destination == destination,
           now - last.at < .milliseconds(250) {
            return
        }
        Self.lastInspectorToggle = (destination, now)

        if inspectorSheet != destination {
            inspectorSheet = destination
        } else {
            inspectorSheet = nil
        }
    }

    /// Open while a deliberate skip is in flight, so the player hard-swaps the
    /// artwork instead of crossfading it. The on-screen transport buttons hold
    /// their own local window; this one exists for the ⌘← / ⌘→ menu commands,
    /// which live in `Commands` and have no way to reach `LargePlayerView`'s
    /// state.
    @MainActor var isSkippingTrack = false
    @MainActor private var skipWindowTask: Task<Void, Never>?

    /// Suppresses the artwork crossfade until the skipped-to track has landed.
    /// The duration matches the transport buttons: the speaker pushes the new
    /// item over the metadata socket well after the command itself returns, and
    /// `ArtworkView` snapshots the fade flag at that moment.
    @MainActor
    func beginSkipWindow(_ duration: Duration = .milliseconds(1500)) {
        skipWindowTask?.cancel()
        isSkippingTrack = true
        skipWindowTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isSkippingTrack = false
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

