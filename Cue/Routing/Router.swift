import Foundation
import SwiftUI
import Observation
import SonosKit
import MusicSearchKit


/// Which tab the window is showing.
enum AppTab: Hashable {
    /// Where the library is set up and reached from — the first tab.
    case home
    case search
    case browse
    /// Stations from every source in one place: Sonos favorites, the
    /// stations near the user and TuneIn's directory, Apple Music's, and
    /// Sonos Radio's. Shown while any of those providers is switched on.
    case radio
    /// A provider the user added to the tab view, as one tab: its library's
    /// front page (Artists, Albums, … as rows). This is the tab bar's entry
    /// on iPhone, where a section's worth of tabs would overflow the bar.
    case provider(MediaSearchService)
    /// One collection of an added provider — the tabs its sidebar section is
    /// split into on iPad and Mac.
    case providerCollection(MediaSearchService, ProviderCollection)

    /// The provider a tab belongs to, so a provider leaving the tab view can
    /// take its selection with it.
    var provider: MediaSearchService? {
        switch self {
        case .home, .search, .browse, .radio: nil
        case let .provider(service): service
        case let .providerCollection(service, _): service
        }
    }
}

@Observable public final class Router {
    static var main = Router()
    static var search = Router()
    static var secondary = Router()
    static var browse = Router()

    var selectedID: String?
    /// The selected tab. On `Router.main` only — the per-screen routers
    /// (`search`, `browse`) navigate within a tab and have no say over which
    /// one is showing.
    var selectedTab: AppTab = .home
    /// Drives the local player's `fullScreenCover`. Presentation state, so it
    /// belongs beside `presentedSheet` rather than in the tab bar accessory
    /// that happens to open it — the accessory is re-hosted by the system, and
    /// state living there went down with it.
    var isPlayerPresented = false
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

    /// Cue was opened to search (the Home Screen quick action), so Quick
    /// Launch leaves the player closed this time. Cleared when Cue goes to
    /// the background.
    @MainActor var openedToSearch = false

    /// Shows the Search tab with its field focused: the Home Screen's Search
    /// quick action and `cue://search` links. Search used to be a sheet on
    /// this router and they still asked for one after it became a tab, but
    /// nothing presents this router's sheets any more (each tab has its own),
    /// so they did nothing. Closes the player and the sheets that would cover
    /// the tab first.
    @MainActor
    func openSearch(focusingField: Bool = true) {
        openedToSearch = true
        isPlayerPresented = false
        presentedSheet = nil
        Router.browse.presentedSheet = nil
        Router.search.presentedSheet = nil
        Router.search.path.removeAll()
        selectedTab = .search
        if focusingField {
            SearchActivator.shared.requestFocus()
        }
    }

    /// What a tap on the already-selected tab does. Reselection is the iOS
    /// convention for "take me to the top of this tab": Search focuses its
    /// field, the way Music does. The other tabs have nothing to do yet —
    /// scrolling their list to the top would go here.
    ///
    /// Reaching `SearchActivator` rather than holding the signal here is
    /// deliberate: there are four `Router` instances, and `SearchScreen` reads
    /// `Router.search` from the environment while the tab bar drives
    /// `Router.main`. A counter on one of them would be bumped on the instance
    /// the screen isn't watching.
    @MainActor
    func handleReselection(of tab: AppTab) {
        switch tab {
        case .search: SearchActivator.shared.requestFocus()
        case .home, .browse, .radio, .provider, .providerCollection: break
        }
    }

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

