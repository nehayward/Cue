import Analytics
import Defaults
import Nuke
import CloudStorage
import VibesDS
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import MusicKit
import MusicSearchKit
import StoreKit
import SwiftUI
import CoreSpotlight
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Tab bar accessory mini player for wherever the route points: this device,
/// or the Sonos group chosen in the route button. Tapping the track opens the
/// player; the trailing controls act in place.
///
/// One row for either, read through `PlaybackRoute.presented` like the
/// player: a route switch changes what it reads, and while a hand-off
/// carries the queue across it stays on the song being carried, with where
/// it's going under the title.
struct MusicPlaybackView: View {
    @Environment(\.tabViewBottomAccessoryPlacement) var placement
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The same key each tab's queue panel reads.
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var showQueue: Bool = false
    /// Owned by `CueApp`, not by this view. The tab bar accessory is hosted
    /// outside the tab content and gets re-created when its placement changes
    /// or the scene comes back to the foreground — `@State` here reset to
    /// `false` on that rebuild and took the presented player down with it.
    @Binding var showPlayer: Bool
    /// Owned by `CueApp` too, because the zoom's other half — the
    /// `fullScreenCover` — is declared up there now.
    let zoomNamespace: Namespace.ID

    /// Singletons rather than the environment: the accessory is hosted
    /// outside what `withEnvironments()` installs on the tab content.
    private var route: PlaybackRoute { .shared }
    private var sonosService: SonosService { .shared }

    var body: some View {
        HStack(spacing: 12) {
            nowPlayingContent

            // Always present, playing or not: the route is set ahead of Play,
            // which is the whole point of it no longer asking.
            PlaybackRouteButton()
                .buttonStyle(.plain)
                .font(.title3)

            // The queue panel's show/hide on iPad, where there is no sidebar
            // header to hold it. Only at a regular width: a compact window
            // has no side panel to show. The Mac has it in the window
            // toolbar and the View menu.
#if !targetEnvironment(macCatalyst)
            if UIDevice.current.userInterfaceIdiom == .pad, horizontalSizeClass == .regular {
                Button {
                    withAnimation(.snappy) {
                        showQueue.toggle()
                    }
                } label: {
                    // The player's queue gauge: how far through the queue
                    // playback is, for what's on screen.
                    PresentedQueueIconView()
                        .font(.title3)
                        // Shown: a soft accent disc behind the gauge rather
                        // than the gauge itself in accent, so its number stays
                        // easy to read.
                        .padding(5)
                        .background(Color("Accent").opacity(showQueue ? 0.25 : 0), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: showQueue)
                .accessibilityLabel(showQueue ? "Hide Queue" : "Show Queue")
                .accessibilityAddTraits(showQueue ? .isSelected : [])
            }
#endif
        }
        .padding(.horizontal, 12)
        // Lifts the row a little so the line below has room of its own
        // rather than crowding the subtitle.
        .padding(.bottom, showsBottomProgressLine ? 6 : 0)
        .frame(maxWidth: 500, maxHeight: 120)
        // On iPhone the line runs the whole width of the accessory, along
        // its bottom edge; the wider iPad and Mac bars keep it under the
        // track text. Inset by the row's own 12pt, so it starts under the
        // artwork's edge and ends under the last button's.
        .overlay(alignment: .bottom) {
            if showsBottomProgressLine {
                progressLine
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    private var progressSpansFullWidth: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var showsBottomProgressLine: Bool {
        progressSpansFullWidth && placement != .inline
    }

    /// The progress line for what's on screen, in seconds whichever it is.
    @ViewBuilder
    private var progressLine: some View {
        let controller = route.presented
        // Through a hand-off, from where the switch was made: the source is
        // paused on its way out, and the target picks up from there.
        let hold = route.hold
        if controller.nowPlayingDisplay != nil {
            MiniPlayerProgressLine(
                duration: controller.duration,
                isRunning: hold?.wasPlaying ?? controller.isClockRunning,
                position: { hold?.position(at: .now) ?? controller.position() }
            )
        }
    }

    /// Under the title: where a hand-off is taking the song while it runs,
    /// else the speaker's name for a speaker and the artist here.
    private func subtitle(for item: PlayableContent?, on group: GroupRoom?) -> String? {
        if route.isHolding {
            return "Moving to \(route.group?.nameWithCount ?? "This Device")…"
        }
        if let group {
            return group.nameWithCount
        }
        return item?.subtitle
    }

    /// The glyph in the cover's place with nothing playing.
    private func idleSymbol(for group: GroupRoom?) -> String {
        guard let group else { return "iphone.radiowaves.left.and.right" }
        return group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill"
    }

    // MARK: - Now playing

    /// The track and its transport. The display item, not the queue row: a
    /// station reads as the song on air here just as it does in the player.
    /// `GroupRoom` is `@Observable`, so a speaker's pushed track and playing
    /// state redraw this in place.
    @ViewBuilder
    private var nowPlayingContent: some View {
        let controller = route.presented
        let group = controller.group
        let item = controller.nowPlayingDisplay
        // While a hand-off holds the row on its source, the source is on its
        // way out: the buttons rest and Play reads as it did.
        let hold = route.hold
        let isPlaying = hold?.wasPlaying ?? controller.isPlaying

        Button {
            showPlayer.toggle()
        } label: {
            HStack(spacing: 12) {
                // A switch with nothing to carry across has nothing to keep
                // on screen meanwhile.
                if group != nil, route.isSwitching, hold == nil {
                    ProgressView()
                        .frame(width: 40, height: 40)
                } else if let item {
                    ContentArtworkView(content: item, showMusicSource: false)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: idleSymbol(for: group))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(item?.title ?? "Not Playing")
                        .font(item == nil ? .callout : .callout.bold())
                        .foregroundStyle(item == nil ? .secondary : .primary)
                        .lineLimit(1)
                    if placement != .inline, let line = subtitle(for: item, on: group) {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !progressSpansFullWidth {
                            progressLine
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .zoomSource(.miniPlayer, in: zoomNamespace)

        if controller.isActive {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task { await controller.togglePlayback() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(GroupMediaControlsView.animatesPlayPause ? .symbolEffect(.replace) : .identity)
                    .sustainedPulse(isActive: GroupMediaControlsView.animatesPlayPause && (hold != nil || controller.isLoading))
            }
            .buttonStyle(.plain)
            .font(.title3)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .disabled(hold != nil)

            if placement != .inline {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task {
                        await controller.next()
                        // Nothing may be listening to the speaker with the
                        // player closed; this brings the new song in.
                        if let group = controller.group {
                            try? await sonosService.updateGroups(from: [group])
                        }
                    }
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)
                .accessibilityLabel("Next")
                .disabled(!controller.hasNext || hold != nil)
            }
        }
    }
}

@main
struct CueApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.openWindow) var openWindow
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.liveActivityManager) var liveActivityManager

    @State private var router: Router = Router.main
    @State private var subscriptionService = SubscriptionService.shared
    @State private var alertService = AlertService.shared
    @State private var musicSearchService = MusicSearchService.shared
    @State private var sonosService = SonosService.shared

    private var audioPlaybackService = AudioPlaybackService.shared
    private var playlistContainer = PlaylistContainer.shared
    private var playHistoryService = PlayHistoryService.shared
    private var miniPlayerManager = MiniPlayerManger.shared

    @CloudStorage(CloudKeys.hasSubscription) private var activeSubscription: Bool = false
    @CloudStorage(CloudKeys.scenes) var scenes: [SonosScene] = []
    
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false
    /// Onboarding, shown once on first launch. Presented from the `TabView`
    /// with its own flag, like the player: the shared router's full-screen
    /// cover is only attached inside some tabs.
    @State private var isOnboardingPresented = false

    /// Onboarding hasn't finished. It runs the speaker search itself, after
    /// explaining the Local Network prompt, so the launch and scene-phase
    /// paths keep out of the way until then.
    private var isOnboarding: Bool {
        !hasOnboarded || OnboardingDebug.forceShow
    }
    @AppStorage("CueMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    @AppStorage(AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    /// True at launch and while Cue is in the background, so Quick Launch
    /// opens the player once per return rather than after every Control
    /// Center pull or notification, which pass through `.inactive`.
    @State private var quickLaunchPending = true
    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
    @AppStorage(AppStorageKeys.savedGroupID) private var savedGroupID: String?

    @State private var previousCount: Int = 0
    
#if targetEnvironment(macCatalyst)
    private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared

    /// Composite key driving `.task(id:)` for the dock menu. Reading these
    /// properties during body eval registers SwiftUI observation, so any
    /// change re-fires the refresh task.
    private var dockRefreshKey: DockMenuCoordinator.RefreshKey {
        let group = router.selectedID.flatMap { id in sonosService.sorted.first(where: { $0.coordinatorID == id }) }
        return .init(
            selectedGroupID: router.selectedID,
            trackUnique: group?.coordinatorRoom.track.unique,
            isPlaying: group?.coordinatorRoom.isPlaying ?? false,
            availableGroupIDs: sonosService.sorted.map { $0.coordinatorID }
        )
    }
#endif
    
    /// Shared by the zoom's two halves: the source in the tab bar accessory and
    /// the `fullScreenCover` on the `TabView` below.
    @Namespace private var zoomNamespace

    @State private var coreFeatures = CoreFeatures.shared
    @State private var offline = OfflineMode.shared
    /// Settings › Appearance › Show Radio Tab.
    @AppStorage(AppStorageKeys.showRadioTab) private var showRadioTab: Bool = true
    /// The sidebar's edits — which of the provider tabs show, and the order
    /// of their sections — kept across launches. This is the whole of tab
    /// customization: the sidebar's own edit mode writes it, and the
    /// provider front pages read it back (`shownCollections(of:)`).
    @AppStorage(AppStorageKeys.tabViewCustomization) private var tabCustomization = TabViewCustomization()

    /// The providers with a section in the sidebar: every one that browses
    /// by collection and is switched on in Services, in the order the app
    /// lists services. Nothing is added or removed by hand any more — a
    /// provider comes with being switched on, and which of its tabs show is
    /// the sidebar's edit mode's to decide.
    private var tabProviders: [MediaSearchService] {
        MediaSearchService.supported.filter { $0.canBeTab && coreFeatures.isEnabled($0) }
    }

    /// The collections a provider's own tab lists on its front page: the
    /// ones its sidebar section is showing. Read from the customization —
    /// a tab the user hid there is left off, one they showed is added — with
    /// `defaultTabCollections` standing in where they haven't decided.
    private func shownCollections(of service: MediaSearchService) -> [ProviderCollection] {
        let defaults = service.defaultTabCollections
        return service.tabCollections.filter { collection in
            switch tabCustomization[tab: service.tabCustomizationID(for: collection)].sidebarVisibility {
            case .visible: true
            case .hidden: false
            case .automatic: defaults.contains(collection)
            @unknown default: defaults.contains(collection)
            }
        }
    }

    /// Whether the Radio tab has a source to draw on: TuneIn or Apple Music
    /// switched on in Services. Those are the two whose stations play on
    /// this device as well as on a speaker, which is the tab's rule — Sonos
    /// Radio and Sonos favorites are speaker-only and stay on Browse and
    /// Search. The user can hide it in Settings › Appearance, and it goes
    /// on its own while Offline Mode is active: every station streams, so
    /// there is nothing there to play.
    private var showsRadioTab: Bool {
        showRadioTab
            && !offline.isActive
            && [MediaSearchService.tuneIn, .apple].contains { coreFeatures.isEnabled($0) }
    }

    /// Search. The search role only on the phone, where it draws the tab as
    /// the bar's separate search bubble. Elsewhere the role exists to hoist
    /// a `.searchable` out of the tab, and `SearchScreen` draws its own
    /// field: on iPad that broke the screen, and on the Mac it took the tab
    /// out of the sidebar's list. A plain tab there.
    @TabContentBuilder<AppTab>
    private var searchTab: some TabContent<AppTab> {
        Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: isPhone ? TabRole.search : nil) {
            Screens.search
        }
    }

    /// Radio: every station source in one place. Fixed like Search and
    /// Browse — no `customizationID` — but only while a radio provider is
    /// switched on in Services.
    @TabContentBuilder<AppTab>
    private var radioTab: some TabContent<AppTab> {
        if showsRadioTab {
            Tab("Radio", systemImage: "radio", value: AppTab.radio) {
                Screens.radio
            }
        }
    }

    /// The Providers section, on iPad and Mac: one tab per switched-on
    /// provider, opening its front page. Apple's sidebar only lets tabs be
    /// dragged within a section, so this is what makes the providers
    /// reorderable there — and hideable, each with a `customizationID`. In
    /// the collapsed tab bar these same tabs are the bar's entries.
    @TabContentBuilder<AppTab>
    private var providersSection: some TabContent<AppTab> {
        TabSection {
            ForEach(tabProviders, id: \.self) { service in
                Tab(value: AppTab.provider(service)) {
                    Screens.providerRoot(service, collections: shownCollections(of: service))
                } label: {
                    providerTabLabel(service)
                }
                .customizationID(service.tabCustomizationID)
            }
        } header: {
            Text("Providers")
        }
        .customizationID(Self.providersSectionCustomizationID)
    }

    private static let providersSectionCustomizationID = "cue.section.providers"

    /// A provider's collection section, on iPad and Mac: a tab per
    /// collection, so the sidebar can jump straight to Albums. Hidden from
    /// the tab bar, where the provider's own tab in the Providers section
    /// stands for all of them. Every tab carries a `customizationID`, which
    /// is what lets the sidebar's edit mode hide and reorder them; the
    /// collections outside `defaultTabCollections` start hidden and wait
    /// there to be switched on. The section's own ID is what lets Edit drag
    /// it above or below the other providers' sections.
    @TabContentBuilder<AppTab>
    private func collectionSection(for service: MediaSearchService) -> some TabContent<AppTab> {
        let collections = shownCollections(of: service)
        let defaults = service.defaultTabCollections

        TabSection {
            ForEach(service.tabCollections, id: \.self) { collection in
                Tab(collection.title, systemImage: collection.systemImage, value: AppTab.providerCollection(service, collection)) {
                    Screens.providerCollection(service, collections: collections, collection: collection)
                }
                .customizationID(service.tabCustomizationID(for: collection))
                .defaultVisibility(.hidden, for: .tabBar)
                .defaultVisibility(defaults.contains(collection) ? .visible : .hidden, for: .sidebar)
            }
        } header: {
            Text(service.title)
        }
        .customizationID(service.tabSectionCustomizationID)
    }

    /// A provider tab's label. A bare `Image`: the tab bar pulls the image
    /// out of the label and draws nothing for a sized or tinted view around
    /// it.
    private func providerTabLabel(_ service: MediaSearchService) -> some View {
        Label {
            Text(service.title)
        } icon: {
            service.tabImage
        }
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Home, the provider sections and the sidebar's Edit — off everywhere
    /// for now. Every device has the phone's three tabs, Browse, Search and
    /// Radio, with providers reached from Browse's menu; the Mac shows them
    /// in its sidebar (`AdaptiveTabViewStyle`), iPhone and iPad in the tab
    /// bar. The adaptable sidebar's rebuild on an iPad resize (a
    /// size-class change folds the sidebar's tabs into a tab bar) was also
    /// crashing UIKit with a nil tab bar item. Kept as a switch for when
    /// the sections come back.
    private var showsLibrarySections: Bool { false }

    /// The tab the selection falls back to: Home where the sidebar has
    /// one, Browse on the tab bar, which has none.
    private var fallbackTab: AppTab {
        showsLibrarySections ? .home : .browse
    }

    /// Every tab the view builds right now. The selection is checked
    /// against this before the `TabView` sees it: a selection naming a tab
    /// that isn't there — a provider switched off in Services, a collection
    /// tab hidden in the sidebar's Edit while it was showing, Home's "Open"
    /// on a provider that's out — is what UIKit's tab bar asserts on ("No
    /// view controller matches the UITabBarItem"), and it asserts during
    /// layout, before any `onChange` gets a chance to move the selection.
    private var availableTabs: Set<AppTab> {
        var tabs: Set<AppTab> = [.search, .browse]
        if showsRadioTab {
            tabs.insert(.radio)
        }
        if showsLibrarySections {
            tabs.insert(.home)
            for service in tabProviders {
                tabs.insert(.provider(service))
                for collection in shownCollections(of: service) {
                    tabs.insert(.providerCollection(service, collection))
                }
            }
        }
        return tabs
    }

    /// The router's selection, or the fallback when it names a tab that
    /// isn't built.
    private func resolvedTab(_ tab: AppTab) -> AppTab {
        availableTabs.contains(tab) ? tab : fallbackTab
    }

    /// The `TabView`'s selection: the router's, clamped to a tab that exists,
    /// with a tap on the already-selected tab reported as a reselection.
    /// SwiftUI has no reselection callback and reports the tap as a set to
    /// the same value, which is why the setter compares before writing.
    private var tabSelection: Binding<AppTab> {
        Binding {
            resolvedTab(router.selectedTab)
        } set: { newValue in
            guard newValue != resolvedTab(router.selectedTab) else {
                router.handleReselection(of: newValue)
                return
            }
            router.selectedTab = newValue
        }
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var router = router
            TabView(selection: tabSelection) {
                if !showsLibrarySections {
                    // The phone's three on every device, Browse first in
                    // Home's place: providers are browsed from Browse's menu
                    // and set up in Settings › Services. No provider tabs, so
                    // the bar never overflows into More. The house is
                    // Browse's here, since it is the home.
                    Tab("Browse", image: "home.fill", value: AppTab.browse) {
                        Screens.browse
                    }
                    searchTab
                    radioTab
                } else {
                    Tab("Home", image: "home.fill", value: AppTab.home) {
                        Screens.home
                    }
                    searchTab
                    Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                        Screens.browse
                    }
                    radioTab

                    // The providers twice over, both driven by the switched-on
                    // set: once as tabs in one section, which is how the
                    // sidebar lets them be reordered and hidden, and then a
                    // collection section per provider. One turned off in
                    // Services drops out of both; its sidebar edits stay in
                    // the customization for when it comes back.
                    providersSection
                    ForEach(tabProviders, id: \.self) { service in
                        collectionSection(for: service)
                    }
                }
            }
            // Customization only with the library sections: it holds the
            // sidebar's edits, and with three fixed tabs there's no Edit.
            .tabViewCustomization(showsLibrarySections ? $tabCustomization : nil)
            .onChange(of: availableTabs) { _, tabs in
                // A tab that left takes its selection with it. The binding
                // already shows the fallback in that case; this keeps the
                // stored value honest so nothing else acts on a tab that's
                // gone.
                if !tabs.contains(router.selectedTab) {
                    router.selectedTab = fallbackTab
                }
            }
            // The queue panel is inside each tab (`Screens`), not out here:
            // wrapped around the whole `TabView` it took its width from the
            // sidebar's, which then had to overlay the content instead of
            // sitting beside it.
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                MusicPlaybackView(showPlayer: $router.isPlayerPresented, zoomNamespace: zoomNamespace)
            }
//            // Above the tabs, not in one of them: a toolbar belongs to the
//            // navigation stack of whichever tab is on screen, so the only way
//            // to keep one field in every tab is to host it out here.
//            .safeAreaInset(edge: .top) {
//                GlobalSearchField(selectedTab: $selectedTab)
//            }
            .tabViewSidebarHeader {
                HStack(spacing: 10) {
                    Image("CueIconGlass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    Text("Cue")
                        .font(.title3.bold())
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            // The speaker-group count footer is off for now; the slot is
            // still the place for it when it comes back.
//            .tabViewSidebarFooter {
//                let count = sonosService.sorted.count
//                Label(
//                    count == 1 ? "1 Speaker Group" : "\(count) Speaker Groups",
//                    systemImage: count == 0 ? "hifispeaker.slash" : "hifispeaker.2"
//                )
//                .font(.footnote)
//                .foregroundStyle(.secondary)
//                .padding(.vertical, 4)
//            }
            // No bottom bar: the queue toggle is in the sidebar header.
            // The sidebar's selection highlight is drawn in the tint, so this
            // is what takes it off accent-teal. A TabView sidebar has no way to
            // colour the row's label separately from its fill, so this gets the
            // subtle neutral capsule but not Music.app's accent-coloured label.
            // The tint reaches the whole TabView, which is why the tab content
            // and the bottom bar put the real accent back — `Color("Accent")`
            // by name, since `.accentColor` now resolves to this tint.
//            .tint(Color.primary.opacity(0.12))
            // The queue panel, beside the whole `TabView`. Inside
            // `withEnvironments()`, which the panel's view reads from.
            .modifier(WindowQueuePanel())
            .withEnvironments()
            .environment(\.zoomNamespace, zoomNamespace)
            // Presented from the `TabView`, not from inside the tab bar
            // accessory. The system re-hosts that accessory when its placement
            // changes or the scene returns to the foreground, and a
            // `fullScreenCover` declared there is re-created with it — which
            // tore the player down and put it back on every background/
            // foreground round trip. The `TabView` is stable, so the
            // presentation survives.
            //
            // It also removes the reason the zoom needed guarding: the morph
            // only happens when the cover presents, and the cover no longer
            // re-presents behind the user's back.
            .fullScreenCover(isPresented: $router.isPlayerPresented) {
#if targetEnvironment(macCatalyst)
                // Plain slide-up on the Mac: the zoom out of the tab bar
                // accessory misbehaves under Catalyst, and the cover's
                // default transition is the one Mac users expect anyway.
                PlayerView()
                    .presentationBackgroundInteraction(.enabled)
#else
                PlayerView()
                    .presentationBackgroundInteraction(.enabled)
                    .zoomTransition(from: .miniPlayer, in: zoomNamespace)
#endif
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                WelcomeScreen()
                    .withEnvironments()
            }
            .modifier(AdaptiveTabViewStyle())
            // Settings ▸ Appearance. Applied to the windows, so everything
            // presented from them follows it too.
            .onChange(of: colorScheme, initial: true) { _, preference in
                preference.apply()
            }
            // Quick Launch's own hook. `handleScenePhase`, which used to run
            // it, isn't attached to this scene (it went with the old launch
            // block), so the setting did nothing.
            .onChange(of: scenePhase, initial: true) { _, phase in
                quickLaunch(on: phase)
            }
            .onOpenURL(perform: handle)
            .onAppear {
                coreFeatures.restoreDeviceServicesOnce()
                // Asks whether there are speakers before anything looks for
                // them. Onboarding writes `hasOnboarded` however it ends,
                // so this is once per install, and starts monitoring itself
                // when it closes.
                if isOnboarding {
                    isOnboardingPresented = true
                } else {
                    SonosService.shared.monitor()
                }
                
#if os(iOS) && !targetEnvironment(macCatalyst)
                // One call for the lifetime of the process: the service watches
                // the model itself from here on and puts the playing Sonos
                // group on the Lock Screen / Control Center card. Deliberately
                // not a view modifier — SwiftUI stops evaluating bodies in the
                // background, which is exactly when the card matters. This
                // was lost with the rest of the old launch block below, and
                // without it the card never appeared for speaker playback.
                NowPlayingSessionService.shared.activate()
#endif
            }
            //            .withAlert()
        }
//            .onOpenURL(perform: handle)
//            .onAppear {
//                guard !AppBootstrapper.shared.didLaunch else { return }
//                AppBootstrapper.shared.didLaunch = true
//                AppBootstrapper.shared.bootstrap()
//
//#if os(iOS) && !targetEnvironment(macCatalyst)
//                // One call for the lifetime of the process: the service watches
//                // the model itself from here on. Deliberately not a view
//                // modifier — SwiftUI stops evaluating bodies in the background,
//                // which is exactly when the Lock Screen card matters.
//                NowPlayingSessionService.shared.activate()
//#endif
//
//                // Wire callbacks before the onboarding gate so events fired
//                // during onboarding (Sonos discovery forming the first group,
//                // a paywall-step purchase) don't fall on the floor.
//                SonosService.shared.groupsChanged = { groups in
//                    guard subscriptionService.subscription.isActive else { return }
//                    liveActivityManager.createActivity(shouldLoad: false)
//                }
//
//                SubscriptionService.shared.subscriptionUpdated = { subscription in
//                    activeSubscription = subscription.isActive
//#if canImport(WidgetKit)
//                    if #available(visionOS 26.0, *) {
//                        WidgetCenter.shared.reloadAllTimelines()
//                    }
//#endif
//                }
//                
//                Task.detached(priority: .utility) {
//                    await LatestReleaseFetcher.refresh()
//                }
//
//                if !hasOnboarded || OnboardingDebug.forceShow {
//                    router.presentedFullScreenCover = .onboard
//                    return
//                }
//
//                Task { @MainActor in
//                    try? await SubscriptionService.shared.checkSubscription()
//                }
//
//#if targetEnvironment(macCatalyst)
//                if isMenuBarAppEnabled {
//                    Task {
//                        try? await Task.sleep(for: .seconds(2))
//                        do {
//                            try await menuAppLaunchAtLoginManager.bridge?.openCueMiniApp()
//                        } catch {
//                            print("Failed to launch CueMini: \(error.localizedDescription)")
//                        }
//                    }
//                }
//                if let bridge = menuAppLaunchAtLoginManager.bridge {
//                    DockMenuCoordinator.shared.install(
//                        bridge: bridge,
//                        router: router,
//                        sonosService: sonosService
//                    )
//                }
//#endif
//                // Try and restore selected groupID
//                if let savedGroupID = savedGroupID {
//                    Task {
//                        let startTime = Date.now
//                        while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 5 {
//                            try? await Task.sleep(for: .milliseconds(100))
//                        }
//
//                        if sonosService.sorted.contains(where: { $0.coordinatorID == savedGroupID }) {
//                            router.selectedID = savedGroupID
//                        }
//                    }
//                }
//
//                // iPad/Mac: Auto-select first group and restore queue state
//                if UIDevice.current.userInterfaceIdiom != .phone {
//                    Task {
//                        let startTime = Date.now
//                        while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 5 {
//                          try? await Task.sleep(for: .milliseconds(100))
//                        }
//                        try? await Task.sleep(for: .milliseconds(400))
//
//                        // Auto-select first group if none selected (iPad initial launch)
//                        if router.selectedID == nil {
//                            sonosService.selectedGroup = sonosService.sorted.first
//                            router.selectedID = sonosService.sorted.first?.coordinatorID
//                        }
//
//                        // Restore queue inspector if it was open
//                        if queueInspectorVisible {
//                            if let savedGroupID = savedGroupID,
//                               let group = sonosService.sorted.first(where: { $0.coordinatorID == savedGroupID }) {
//
//                                router.inspectorSheet = .queue(group: group)
//                            } else if let selectedID = router.selectedID,
//                                      let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) {
//                                // Fall back to currently selected group
//                                router.inspectorSheet = .queue(group: group)
//                            } else if let firstGroup = sonosService.sorted.first {
//                                // Fall back to first available group
//                                router.inspectorSheet = .queue(group: firstGroup)
//                            }
//                        }
//                    }
//                }
//
//                Task {
//                    CueAppShortcutProvider.updateAppShortcutParameters()
//                }
//            }
//#if targetEnvironment(macCatalyst)
//            .frame(minWidth: 800, minHeight: 500)
//#endif
//            .fontDesign(.rounded)
//            .onContinueUserActivity(CSSearchableItemActionType) { activity in
//                guard let userInfo = activity.userInfo, let itemIdentifier = userInfo[CSSearchableItemActivityIdentifier] as? String else {
//                    return
//                }
//                if itemIdentifier.starts(with: "SonosDeviceEntity/") {
//                    let deviceID = itemIdentifier.replacingOccurrences(of: "SonosDeviceEntity/", with: "")
//                    
//                    Task {
//                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: deviceID) else { return }
//                        router.selectedID = group.coordinatorID
//                    }
//                }
//            }
//            .preferredColorScheme(colorScheme.scheme)
//#if targetEnvironment(macCatalyst)
//            // Single source of truth for dock-menu refresh. The RefreshKey
//            // reads selectedID, the current group's track + isPlaying, and
//            // the list of available groups — so any change re-fires the task,
//            // and SwiftUI auto-cancels any in-flight refresh from the
//            // previous key. `.task` is a View modifier, so it must live
//            // inside WindowGroup, not on the Scene.
//            .task(id: dockRefreshKey) {
//                await DockMenuCoordinator.shared.refresh()
//            }
//#endif
//        }
//        .windowResizability(.contentMinSize)
//        .onChange(of: scenePhase) {
//            handleScenePhase(scenePhase)
//        }
//        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
//            activeSubscription =  newValue.isActive
//        }
//        .onChange(of: router.selectedID) {
//            // No inspector re-targeting here: InspectorContentView (and the
//            // visionOS ornament) resolve the selected group live from
//            // router.selectedID, so the destination enum's captured group is
//            // only a fallback.
//            savedGroupID = router.selectedID
//        }
//        .onChange(of: sonosService.groups) {
//            if sonosService.rooms.count == previousCount {
//                return
//            }
//
//            Analytics.shared.track(.numberOfDevices, with: ["Device Count" : sonosService.rooms.count,
//                                                            "Subscriber": subscriptionService.subscription.isActive])
//            previousCount = sonosService.rooms.count
//        }
//        .onChange(of: sonosService.sortedRooms) {
//            if #available(iOS 18.0, *) {
//                Task {
//                    try? await CSSearchableIndex.default().deleteAllSearchableItems()
//                    try? await CSSearchableIndex.default().indexAppEntities(
//                        sonosService.sortedRooms.map { SonosDeviceEntity(id: $0.id, ip: $0.ip, name: $0.name)}
//                    )
//                }
//            }
//        }
//        .onChange(of: router.inspectorSheet) { oldValue, newValue in
//            if UIDevice.current.userInterfaceIdiom != .phone  {
//                queueInspectorVisible = (newValue?.id == "queue")
//            }
//        }
//        .onChange(of: sonosService.isCellular) { oldValue, isCellular in
//            if isCellular {
//                router.selectedID = nil
//                router.inspectorSheet = nil
//                sonosService.clearDevices()
//                alertService.showAlert(with: "On Cellular", imageName: "wifi.slash")
//            } else if oldValue {
//                // Coming back from cellular to WiFi - restart discovery
//                sonosService.monitor()
//            }
//        }
//        .commands {
//            SidebarCommands()
//            CommandGroup(replacing: .appSettings) {
//                Button {
//                    Router.main.presentedSheet = .settings()
//                } label: {
//                    Label("Settings", systemImage: "gear")
//                }
//                .keyboardShortcut(",", modifiers: .command)
//            }
//            CommandGroup(after: .sidebar) {
//                Divider()
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
//                        router.toggleInspector(.search(group: sonosService.sorted[group]))
//                    }
//                } label: {
//                    Label("\(router.inspectorSheet?.id ?? "" == "search" ? "Hide" : "Show") Search", systemImage: "magnifyingglass")
//                }
//                .keyboardShortcut("s", modifiers: [])
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
//                        router.toggleInspector(.browse(group: sonosService.sorted[group]))
//                    }
//                } label: {
//                    Label("\(router.inspectorSheet?.id ?? "" == "browse" ? "Hide" : "Show") Browse", image: "home.fill")
//                }
//                .keyboardShortcut("b", modifiers: [])
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
//                        router.toggleInspector(.queue(group: sonosService.sorted[group]))
//                    }
//                } label: {
//                    Label("\(router.inspectorSheet?.id ?? "" == "queue" ? "Hide" : "Show") Queue", systemImage: "list.dash")
//                }
//                .keyboardShortcut("q", modifiers: [])
//                
//                Button {
//                    router.sheet(to: .settings(destination: .alarms))
//                } label: {
//                    Label("Show Alarms", systemImage: "alarm.fill")
//                }
//                .keyboardShortcut("a", modifiers: [.shift, .command])
//                
//                Toggle(isOn: $showArtworkOnly) {
//                    Label("Album Cover Only", systemImage: "photo")
//                    Text("Hide titles and controls.")
//                }
//                .keyboardShortcut("f", modifiers: [.shift, .command])
//            }
//            CommandMenu("Playback") {
//                PlaybackTransportControls(router: router, sonosService: sonosService)
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            HapticManager.shared.fireHaptic(.selection)
//                            let newPosition = group.coordinatorRoom.estimatedPlaybackPosition() + 15000
//                            await sonosService.seek(to: newPosition, on: group)
//                        }
//                    }
//                } label: {
//                    Label("Seek Forward", systemImage: "goforward")
//                }
//                .keyboardShortcut(.rightArrow, modifiers: .option)
//                .disabled(router.selectedID == nil)
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            HapticManager.shared.fireHaptic(.selection)
//                            let newPosition = max(0, group.coordinatorRoom.estimatedPlaybackPosition() - 15000)
//                            await sonosService.seek(to: newPosition, on: group)
//                        }
//                    }
//                } label: {
//                    Label("Seek Backward", systemImage: "gobackward")
//                }
//                .keyboardShortcut(.leftArrow, modifiers: .option)
//                .disabled(router.selectedID == nil)
//
//                Divider()
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            var currentPlayMode = group.playMode
//                            if currentPlayMode.contains(.shuffle) {
//                                currentPlayMode.remove(.shuffle)
//                            } else {
//                                currentPlayMode.insert(.shuffle)
//                            }
//                            group.playMode = currentPlayMode
//                            await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
//                        }
//                    }
//                } label: {
//                    Label("Shuffle", systemImage: "shuffle")
//                }
//                .keyboardShortcut("s")
//                .disabled(router.selectedID == nil)
//
//                Button {
//                    Task {
//                        if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                            var currentPlayMode = group.playMode
//                            if !currentPlayMode.isRepeatEnabled {
//                                currentPlayMode.insert(.repeatAll)
//                            } else if currentPlayMode.isRepeatAllEnabled {
//                                currentPlayMode.remove(.repeatAll)
//                                currentPlayMode.insert(.repeatOne)
//                            } else {
//                                currentPlayMode.remove(.repeatOne)
//                                currentPlayMode.remove(.repeatAll)
//                            }
//                            group.playMode = currentPlayMode
//                            await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
//                        }
//                    }
//                } label: {
//                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                        Label("Repeat", systemImage: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
//                    } else {
//                        Label("Repeat", systemImage: "repeat")
//                    }
//                }
//                .keyboardShortcut("r")
//                .disabled(router.selectedID == nil)
//
//                Divider()
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                        router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
//                    }
//                } label: {
//                    Label("Open Album", systemImage: "smallcircle.circle.fill")
//                }
//                .keyboardShortcut("i", modifiers: [.shift, .command])
//                .disabled(router.selectedID == nil)
//
//                Button {
//                    if let id = router.selectedID, let group = sonosService.sorted.first(where: { $0.coordinatorID == id }) {
//                        router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
//                    }
//                } label: {
//                    Label("Open Artist", systemImage: "music.mic")
//                }
//                .keyboardShortcut("i", modifiers: [.command])
//                .disabled(router.selectedID == nil)
//            }
////            CommandGroup(after: .windowArrangement) {
////                Button {
////                    openWindow(id: "mini")
////                } label: {
////                    Text("Mini Player")
////                }
////                .keyboardShortcut("0")
////            }
//        }
////        Window(id: "mini") {
////            VStack {
////                MiniPlayerView()
////                    .environment(SelectedGroupService(group: sonosService.selectedGroup))
////                    .withEnvironments()
////            }
////        }
////        .windowResizability(.contentSize)
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            // Printed like the other two: without it a scene trace reads
            // `Inactive … Monitoring!` with no way to tell whether the app came
            // back or something else restarted the pulse. That ambiguity is what
            // hid `stopMonitoringOffScreen`'s bug.
            print("Active")
            // Speakers are only looked for when Sonos is switched on: looking
            // is what puts up the Local Network permission prompt. Everything
            // after this block runs either way — it used to sit behind an
            // onboarding guard, which also held back the subscription check
            // until onboarding had finished.
            if sonosService.isEnabled, !isOnboarding {
                // The network may have changed while backgrounded (e.g. home →
                // friend's house). Re-race known IPs + discovery on the next poll
                // instead of blocking on a now-stale cached IP. Cheap: an unchanged
                // network still wins in ms, and the flag re-verifies after one load.
                sonosService.invalidateVerifiedConnection()
                // Re-opened before `monitor()`, and before any view `.task` that
                // fires as the app comes back can call it — this runs first on the
                // activation.
                sonosService.allowsMonitoring = true
                sonosService.monitor()
#if targetEnvironment(macCatalyst)
                // Window is open — live monitoring + `.task(id:)` keep the dock
                // menu fresh, so the background poll isn't needed.
                DockMenuCoordinator.shared.stopBackgroundRefresh()
#endif
                Task {
                    let startTime = Date.now
                    while sonosService.sorted.isEmpty && Date.now.timeIntervalSince(startTime) < 10 {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    guard !sonosService.sorted.isEmpty else { return }
                    sonosService.onServerListening()
                }
            
                if FeatureGate.shared.isAvailable(.liveActivities) {
                    Task {
                        for group in sonosService.groups {
                            if !group.coordinatorRoom.isPlaying {
                                await liveActivityManager.stop(id: group.coordinatorRoom.id)
                            }
                        }
                    }
                }
            }

            Task {
                try? await subscriptionService.checkSubscription()
            }

            Task {
                try? await Task.sleep(for: .seconds(1))
                ReviewCoordinator.shared.requestReview()
            }
        case .inactive:
            print("Inactive")
#if canImport(WidgetKit)
            if #available(visionOS 26.0, *) {
                WidgetCenter.shared.reloadAllTimelines()
            }
#endif
            Task {
                await liveActivityManager.refresh()
            }
            stopMonitoringOffScreen(scenePhase)
        case .background:
            print("Background")
            stopMonitoringOffScreen(scenePhase)
#if targetEnvironment(macCatalyst)
            // Monitoring is now cancelled, so the cached model freezes. Poll
            // the selected group on a slow cadence to keep the dock menu
            // current (it's built synchronously and can't fetch on open).
            DockMenuCoordinator.shared.startBackgroundRefresh()
#endif
        @unknown default:
            break
        }
    }

    /// Stops the SOAP pulse and the volume watcher, which exist to feed on-screen
    /// UI and are the app's most expensive recurring work — `load()` plus a
    /// per-group sweep every 500–800 ms.
    ///
    /// Called for `.inactive` as well as `.background`, because **the phone
    /// locking with Cue frontmost does not reliably reach `.background`**. With
    /// the Lock Screen card's audio session held the scene often parks at
    /// `.inactive` instead, and keying the teardown on `.background` alone left
    /// both loops polling with the screen off — sometimes for the whole time the
    /// phone was locked. The scene trace behind that bug reads
    /// `Inactive, Inactive, Inactive` with no `Background` at all.
    ///
    /// A transient `.inactive` — a notification banner, a Control Centre pull,
    /// the app switcher — costs one `monitor()` restart on the way back, the
    /// same as any foreground return. That is cheap, and much cheaper than the
    /// case this exists to stop.
    ///
    /// Not on iPad: there, `.inactive` is also what a *visible* window in Split
    /// View or Stage Manager reports when it merely isn't the focused one, and
    /// freezing a window the user can see would be a real regression. iPad keeps
    /// the old `.background`-only behaviour until there's a signal that
    /// separates "not focused" from "not on screen".
    ///
    /// Nothing to stop while Sonos is switched off. Nor during onboarding: its
    /// discovery page puts up the Local Network prompt, which makes the scene
    /// `.inactive`, and `.active` leaves monitoring to onboarding — so a
    /// teardown here would stop the search with nothing to start it again.
    @MainActor
    private func stopMonitoringOffScreen(_ phase: ScenePhase) {
        guard sonosService.isEnabled, !isOnboarding else { return }
        if phase == .inactive, UIDevice.current.userInterfaceIdiom == .pad { return }

        // Shut the gate before cancelling, not after: cancelling only stops the
        // loops that are running, and `monitor()` is called from a dozen places
        // — a Search button, several view `.task`s, the cellular-recovery
        // handler — any of which would restart them behind a locked screen.
        // `SonosService.allowsMonitoring` is what makes this a guarantee rather
        // than a race.
        sonosService.allowsMonitoring = false
        sonosService.sonosPulse.cancel()
        sonosService.watcher.cancel()
    }

    /// Settings ▸ Quick Launch: opens the player when Cue launches or comes
    /// back from the background.
    @MainActor
    private func quickLaunch(on phase: ScenePhase) {
        switch phase {
        case .background:
            quickLaunchPending = true
        case .active:
            guard quickLaunchPending else { return }
            quickLaunchPending = false
            guard speedLaunchNowPlaying, !isOnboarding else { return }
            openNowPlaying()
        default:
            break
        }
    }

    /// Opens the player. It shows whatever the route points at — this
    /// device's queue or the speaker last chosen — so there's nothing to pick
    /// here, and with nothing queued it's the empty player, controls and all.
    @MainActor
    private func openNowPlaying() {
        router.isPlayerPresented = true
    }

    @MainActor
    private func handle(_ url: URL) {
        Task {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            
            // `updateGroups` returns at once while Sonos is switched off.
            if sonosService.groups.isEmpty {
                try? await sonosService.updateGroups()
            }
            
            if components.host?.lowercased() == "playing" {
                openNowPlaying()
                return
            }
            
            // The share extension's Device destination. It can't play locally
            // itself — `ApplicationMusicPlayer` doesn't run in an app extension,
            // and its process ends with the sheet — so it forwards the content
            // here with `device=1` on the usual play/resolve link.
            if components.queryItems?.contains(where: { $0.name == "device" && $0.value == "1" }) == true,
               ["play", "resolve"].contains(components.host?.lowercased() ?? "") {
                let position = components.queryItems?
                    .first { $0.name == "position" }?.value
                    .flatMap(QueuePosition.init(linkValue:)) ?? .now
                let source: URL? = if components.host?.lowercased() == "resolve" {
                    components.queryItems?.first { $0.name == "url" }?.value.flatMap(URL.init(string:))
                } else {
                    Self.strippingHandoffQuery(url)
                }
                guard let source else { return }
                await playOnDevice(from: source, position: position)
                return
            }

            if components.host?.lowercased() == "alarms" {
                router.presentedSheet = .settings(destination: .alarms)
                return
            }
            
            if components.host?.lowercased() == "subscribe" {
                router.presentedFullScreenCover = .paywall
                return
            }
            
            if components.host?.lowercased() == "search", url.pathComponents.contains("favorites") {
                // Navigate to favorite search
                router.path.removeAll()
                router.presentedSheet = .favorites
                return
            }

            if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.presentedSheet = nil
                

                guard let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) else {
                    Task {
                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
                            return
                        }
                        router.selectedID = group.coordinatorID
                        if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                            router.presentedSheet = .search(group: group)
                        } else {
                            router.inspectorSheet = .search(group: group)
                        }
                    }
                    return
                }
                router.selectedID = group.coordinatorID
                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
                    router.presentedSheet = .search(group: group)
                } else {
                    router.inspectorSheet = .search(group: group)
                }
                return
            }

            if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
                router.presentedSheet = nil

                guard let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) else {
                    Task {
                        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
                            return
                        }
                        router.selectedID = group.coordinatorID
                    }
                    return
                }
                router.selectedID = group.coordinatorID
            }
            
            // MARK: Add Back for queue
//            if let roomName = components.host {
//                guard let groupID = components.queryItems?.first(where: { $0.name == "id" })?.value else { return }
//
//                guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: groupID) else {
//                    return
//                }
//
//                if url.pathComponents.contains("queue") || components.queryItems?.contains(where: { $0.name == "showqueue" }) == true {
//                    router.selectedID = group.coordinatorID
//                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.presentedSheet = .queue(group: sonosService.groups[groupIndex])
//                    } else {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.inspectorSheet = .queue(group: sonosService.groups[groupIndex])
//                    }
//                } else if url.pathComponents.contains("search") || components.queryItems?.contains(where: { $0.name == "showsearch" }) == true {
//                    router.selectedID = group.coordinatorID
//                    guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                    router.inspectorSheet = .search(group: sonosService.groups[groupIndex])
//                } else if url.pathComponents.contains("browse") || components.queryItems?.contains(where: { $0.name == "showbrowse" }) == true {
//                    router.selectedID = group.coordinatorID
//                    // Show browse
//                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .vision {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.presentedSheet = .browse(group: sonosService.groups[groupIndex])
//                    } else {
//                        guard let groupIndex = sonosService.groups.firstIndex(where: { $0.coordinatorID == group.coordinatorID }) else { return }
//                        router.inspectorSheet = .browse(group: sonosService.groups[groupIndex])
//                    }
//                } else {
//                    router.selectedID = group.coordinatorID
//                }
//                return
//            }

            if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
                guard let scene = scenes.first(where: { $0.name == name }) else { return }
                Task {
                    if let content = scene.playableContent {
                        alertService.showAlertContent(with: content, subtitle: "Running \(scene.name)", symbolName: "bolt.fill")
                    } else {
                        alertService.showAlert(with: "Running \(scene.name)")
                    }
                    try await sonosService.runScene(scene)
                }
            }

            if components.host?.lowercased() == "play", let paths = components.string?.split(separator: "/").map(String.init), let url = components.url {
                if paths.count < 3 {
                    return
                }
                router.sheet(to: .playMedia(url: url))
            }

            if components.host?.lowercased() == "view", let url = components.url {
                Task {
                    guard let content = await sonosService.getContent(from: url) else { return }
                    if content.content.type == .artist || content.content.type == .libraryArtist {
                        router.sheet(to: .artistDetail(content: content, group: nil))
                    } else if content.content.type.isRadio {
                        // Stations have no detail screen — open the play sheet
                        // so the user can pick a room.
                        router.sheet(to: .playMedia(url: url))
                    } else {
                        router.sheet(to: .mediaDetail(content: content, group: nil))
                    }
                }
            }

            // Fallback for the share extension: when it can't resolve the
            // shared link itself, it forwards the original URL via
            // cue://resolve?url=<encoded>. The main app has full
            // SonosService/MusicKit access and can resolve it here.
            if components.host?.lowercased() == "resolve",
               let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let originalURL = URL(string: raw) {
                router.sheet(to: .playMedia(url: originalURL))
            }

            if components.host?.lowercased() == "group", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.presentedSheet = nil
                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                    router.selectedID = group.coordinatorID
                    router.presentedSheet = .groupScreen(group: group)
                }
                Task {
                    try await sonosService.load(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        router.selectedID = group.coordinatorID
                        router.presentedSheet = .groupScreen(group: group)
                        return
                    }
                }
            }
            
            if components.host?.lowercased() == "services" {
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            }
        }
    }

    /// Strips the routing-only parameters back off, so what's left is the plain
    /// `cue://play/...` link `getContent(from:)` already knows how to resolve.
    private static func strippingHandoffQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let remaining = (components.queryItems ?? []).filter { !["device", "position"].contains($0.name) }
        components.queryItems = remaining.isEmpty ? nil : remaining
        return components.url ?? url
    }

    /// Plays shared content on this device rather than a Sonos group. The
    /// extension only screens out what can *never* play here, so this is where
    /// the real test happens — anything the local queue won't take (Spotify and
    /// friends, a Plex track with no stream URL) falls back to the room picker
    /// instead of failing silently.
    private func playOnDevice(from url: URL, position: QueuePosition) async {
        guard let content = await sonosService.getContent(from: url) else {
            router.sheet(to: .playMedia(url: url))
            return
        }

        do {
            try await LocalPlaybackService.shared.enqueue(content, at: position)
            alertService.showAlertContent(
                with: content,
                subtitle: "Playing on this device",
                symbolName: "iphone.radiowaves.left.and.right"
            )
        } catch LocalPlaybackService.LocalPlaybackError.nothingPlayable {
            // Nothing here can play locally, so fall back to picking a speaker.
            // The sheet applies the same test and will hide its own Device row,
            // which is what we want — offering it again would only fail again.
            router.sheet(to: .playMedia(url: url))
        } catch {
            alertService.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
        }
    }
}

/// `.sidebarAdaptable` on the Mac, where the sidebar is; the plain tab bar
/// on iPhone and iPad, which have none. The adaptable style runs the
/// sidebar's tab model everywhere it is applied — hidden tabs,
/// customization — and a tab that model hides is a tab bar item with no
/// view controller behind it. `.tabBarOnly` on iPad so the bar can't be
/// turned into a sidebar there either.
private struct AdaptiveTabViewStyle: ViewModifier {
    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        content.tabViewStyle(.sidebarAdaptable)
#else
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.tabViewStyle(.tabBarOnly)
        } else {
            content
        }
#endif
    }
}


/// The thin elapsed-time line under the mini player's track text. Units are
/// the caller's (seconds on the device, milliseconds from a speaker) — only
/// the ratio is drawn. A live stream reports no duration, so the line keeps
/// its height but stays hidden rather than showing an empty track.
///
/// Drawn from a running estimate (`Room.estimatedPlaybackPosition()` for a
/// speaker, `LocalPlaybackService.progress` for this device) through
/// `PlaybackTimeline`, so it redraws once per pixel of progress and only
/// while it's on screen, the scene is visible and playback is moving. It used
/// to run its own clock on every frame of a `TimelineView` that kept going
/// behind the Lock Screen, since the audio session keeps the app alive there.
private struct MiniPlayerProgressLine: View {
    let duration: TimeInterval
    /// Whether the position is moving on its own right now.
    let isRunning: Bool
    /// How many of the caller's units pass per second of playback: `1` for
    /// seconds, `1000` for milliseconds.
    var unitsPerSecond: Double = 1
    /// Where playback is now, read on every redraw.
    let position: () -> TimeInterval

    @Environment(\.displayScale) private var displayScale
    @State private var width: CGFloat = 0

    private var hasDuration: Bool {
        duration.isFinite && duration > 0
    }

    private func fraction(of position: TimeInterval) -> CGFloat {
        guard hasDuration, position.isFinite else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }

    var body: some View {
        PlaybackTimeline(
            isRunning: isRunning && hasDuration,
            minimumInterval: ProgressRedraw.interval(
                forDuration: duration / unitsPerSecond * 1000,
                length: width,
                scale: displayScale
            ),
            position: position
        ) { position in
            Capsule()
                .fill(.secondary.opacity(0.3))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.primary)
                        .frame(width: width * fraction(of: position))
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(height: 3)
        .padding(.top, 2)
        .opacity(hasDuration ? 1 : 0)
        .accessibilityHidden(true)
    }
}

/// Transport buttons for the "Playback" command menu. Extracted into its own
/// View because inlining all five buttons (each with conditional labels and
/// async closures) pushed the `Commands` builder past the type-checker's
/// reasonable-time limit.
private struct PlaybackTransportControls: View {
    let router: Router
    let sonosService: SonosService

    private var selectedGroup: GroupRoom? {
        guard let id = router.selectedID else { return nil }
        return sonosService.sorted.first { $0.coordinatorID == id }
    }

    var body: some View {
        ControlGroup(selectedGroup?.nameWithCount ?? "No Group Selected") {
            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    if group.coordinatorRoom.isPlaying {
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            } label: {
                let playing = selectedGroup?.coordinatorRoom.isPlaying ?? false
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    // Twin of the transport buttons in LargePlayerView: a
                    // deliberate skip snaps the artwork over rather than
                    // crossfading it.
                    router.beginSkipWindow()
                    await sonosService.previous(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Previous Track", systemImage: "backward.fill")
            }
            .keyboardShortcut(.leftArrow)
            .disabled(router.selectedID == nil)

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    router.beginSkipWindow()
                    await sonosService.next(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Next Track", systemImage: "forward.fill")
            }
            .keyboardShortcut(.rightArrow)
            .disabled(router.selectedID == nil)

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: 5)
                }
            } label: {
                Label("Volume Up", systemImage: "speaker.wave.2.fill")
            }
            .keyboardShortcut(.upArrow)
            .disabled(router.selectedID == nil)

            Button {
                Task {
                    guard let group = selectedGroup else { return }
                    HapticManager.shared.fireHaptic(.selection)
                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: -5)
                }
            } label: {
                Label("Volume Down", systemImage: "speaker.wave.1.fill")
            }
            .keyboardShortcut(.downArrow)
            .disabled(router.selectedID == nil)
        }
    }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if targetEnvironment(macCatalyst)
        // macOS auto-injects "Start Dictation" and "Emoji & Symbols" into any Edit menu. Opt out so
        // ours carries only Undo/Redo. (AutoFill is removed via the menu builder.)
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
        #endif
        // Sonos is opt-in here. This runs before any view body or `.task` can
        // call `monitor()`, which is what would put up the Local Network
        // prompt on a device that has never seen a speaker.
        SonosService.shared.loadEnabledPreference()
        // RevenueCat, analytics, remote flags and the image pipeline. Before
        // any view body: `Purchases.shared` is a fatal error until
        // `Purchases.configure` has run, and Preferences reads it for the
        // app user ID it shows — opening Settings crashed once this stopped
        // being called from the root view's onAppear.
        if !AppBootstrapper.shared.didLaunch {
            AppBootstrapper.shared.didLaunch = true
            AppBootstrapper.shared.bootstrap()
        }
        // The continued-processing task's launch handler has to be in place
        // before a download batch submits it.
        ContinuedDownloadTask.shared.register()
        // Early, so a status the watch sent while Cue was closed, and the
        // end of a library transfer, are delivered.
        WatchSyncService.shared.activate()
        // A Files scan gets the same card: progress on the Lock Screen and
        // the app kept running until it's done. The pass that reads the
        // tags of songs still in iCloud follows the scan on the same card,
        // and gets one of its own when it starts by itself.
        Task { @MainActor in
            let files = FilesLibraryService.shared
            let track: @MainActor () -> Void = {
                ContinuedDownloadTask.shared.trackLibrary(folderName: files.folderName ?? "Music")
            }
            files.onScanStarted = track
            files.onCloudTagsStarted = track
        }
        return true
    }

    /// The system relaunched (or woke) the app because the download
    /// session has events to deliver. Handing the completion handler to the
    /// manager makes it recreate the session, which drains the events; it
    /// calls the handler once they're done.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
    }

    func application(
       _ application: UIApplication,
       configurationForConnecting connectingSceneSession: UISceneSession,
       options: UIScene.ConnectionOptions
     ) -> UISceneConfiguration {
#if os(iOS) && !targetEnvironment(macCatalyst)
         // The car's screen gets its own delegate. Every scene used to get
         // `CueSceneDelegate`, which is a window delegate and can't drive
         // CarPlay's templates.
         if let carPlay = CarPlaySceneDelegate.configuration(for: connectingSceneSession) {
             return carPlay
         }
#endif
         if let shortcutItem = options.shortcutItem {
             if shortcutItem.type == "com.cue.search" {
                 Task { @MainActor in
                     // MARK: Delay for Toolbar
                     try await Task.sleep(for: .milliseconds(200))
                     Router.main.path.removeAll()
                     Router.main.presentedSheet = .search()
                 }
             }
         }

       let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
       sceneConfig.delegateClass = CueSceneDelegate.self // 👈🏻
       return sceneConfig
     }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        /// Only operate on the main menu bar.
        if builder.system == .main {
            // Remove the system Edit menu entirely — macOS force-injects AutoFill / Start Dictation /
            // Emoji & Symbols into any Edit menu. Undo/Redo live in a dedicated Playlist menu instead.
            builder.remove(menu: .edit)
            builder.remove(menu: .format)
            builder.remove(menu: .newScene)
            builder.remove(menu: .open)
            builder.remove(menu: .openRecent)
            builder.remove(menu: .document)

            // View › Show/Hide Queue, ⌥⌘0 as Xcode toggles its inspector.
            // The toolbar item does the same; this is the keyboard's way in.
            let toggleQueueCommand = UIKeyCommand(
                title: QueuePanelVisibility.isShown ? "Hide Queue" : "Show Queue",
                image: UIImage(systemName: "sidebar.trailing"),
                action: #selector(toggleQueue),
                input: "0",
                modifierFlags: [.command, .alternate]
            )
            builder.insertChild(
                UIMenu(title: "", options: .displayInline, children: [toggleQueueCommand]),
                atStartOfMenu: .view
            )

            // Add New Playlist to File menu
            let newPlaylistCommand = UIKeyCommand(
                title: "New Playlist",
                image: UIImage(systemName: "music.note.list"),
                action: #selector(newPlaylist),
                input: "n",
                modifierFlags: .command
            )

            // Add to Last Playlist command (dynamic title)
            let addToLastPlaylistAction: UIMenuElement

            if let last = LastPlaylist.current {
                addToLastPlaylistAction = UIKeyCommand(
                    title: "Add to \(last.title)",
                    image: last.service.uiImage ?? UIImage(systemName: "text.badge.plus"),
                    action: #selector(addToLastPlaylist),
                    input: "s",
                    modifierFlags: [.shift, .command]
                )
            } else {
                addToLastPlaylistAction = UIAction(title: "Add to Last Playlist", attributes: .disabled) { _ in }
            }

            // Add to Playlist submenu with deferred loading
            let addToPlaylistDeferred = UIDeferredMenuElement.uncached { completion in
                Task { @MainActor in
                    let sonosService = SonosService.shared
                    let alertService = AlertService.shared
                    let musicSearchService = MusicSearchService.shared

                    // Get current track from selected group
                    guard let selectedID = Router.main.selectedID,
                          let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
                        completion([
                            UIAction(title: "No Track Playing", attributes: .disabled) { _ in }
                        ])
                        return
                    }

                    let track = group.coordinatorRoom.track.toPlayable

                    // Adds `track` to `playlist`, dispatching to Sonos or the streaming service.
                    func action(for playlist: PlayableContent) -> UIAction {
                        UIAction(title: playlist.title, image: playlist.content.service.uiImage) { _ in
                            Task { @MainActor in
                                let success: Bool
                                if playlist.content.service == .library {
                                    await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
                                    success = true
                                } else {
                                    success = await musicSearchService.addToServicePlaylist(track: track, playlist: playlist)
                                }
                                guard success else {
                                    alertService.showAlert(with: "Couldn’t add to \(playlist.title)", imageName: "exclamationmark.triangle")
                                    return
                                }
                                alertService.showAlertContent(with: track, subtitle: "Added to \(playlist.title)", symbolName: "plus")
                                LastPlaylist.save(playlist)
                                alertService.alert.handleTap = {
                                    Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                                }
                            }
                        }
                    }

                    var menuItems: [UIMenuElement] = []

                    // The track's own streaming-service playlists (Apple Music / Spotify / Plex / Deezer).
                    let service = track.content.service
                    if [.apple, .spotify, .plex, .deezer, .subsonic, .files].contains(service),
                       [.track, .libraryTrack].contains(track.content.type) {
                        let servicePlaylists = await musicSearchService.userPlaylists(for: service)
                        if !servicePlaylists.isEmpty {
                            menuItems.append(UIMenu(title: service.title, options: .displayInline, children: servicePlaylists.map(action)))
                        }
                    }

                    // Sonos playlists accept any track.
                    let sonosPlaylists = await sonosService.sonosPlaylists()
                    if !sonosPlaylists.isEmpty {
                        menuItems.append(UIMenu(title: "Sonos", options: .displayInline, children: sonosPlaylists.map(action)))
                    }

                    if menuItems.isEmpty {
                        menuItems = [UIAction(title: "No Playlists", attributes: .disabled) { _ in }]
                    }

                    completion(menuItems)
                }
            }

            let addToPlaylistMenu = UIMenu(
                title: "Add to Playlist",
                image: UIImage(systemName: "text.badge.plus"),
                children: [addToPlaylistDeferred]
            )

            // A dedicated Playlist menu gathers every playlist action plus Undo/Redo, on all
            // platforms — so ⌘Z works with a hardware keyboard on iPad/iPhone too, not just Catalyst.
            // (We don't reuse the Edit menu: macOS injects AutoFill/Dictation/Emoji into it.)
            // Undo/Redo route through the responder chain (playlistUndo/playlistRedo) and enable via
            // canPerformAction.
            let undoCommand = UIKeyCommand(title: "Undo", action: #selector(playlistUndo), input: "z", modifierFlags: .command)
            let redoCommand = UIKeyCommand(title: "Redo", action: #selector(playlistRedo), input: "z", modifierFlags: [.command, .shift])
            let playlistMenu = UIMenu(title: "Playlist", identifier: UIMenu.Identifier("com.cue.playlistMenu"), children: [
                UIMenu(title: "", options: .displayInline, children: [newPlaylistCommand, addToLastPlaylistAction, addToPlaylistMenu]),
                UIMenu(title: "", options: .displayInline, children: [undoCommand, redoCommand])
            ])
            builder.insertSibling(playlistMenu, afterMenu: .file)
        }
    }

    /// Drives the foreground playlist editor's undo, routed from the Playlist menu / ⌘Z.
    @objc func playlistUndo() {
        PlaylistUndoMenuBridge.shared.editor?.undo()
    }

    /// Drives the foreground playlist editor's redo, routed from the Playlist menu / ⌘⇧Z.
    @objc func playlistRedo() {
        PlaylistUndoMenuBridge.shared.editor?.redo()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(playlistUndo):
            return PlaylistUndoMenuBridge.shared.editor?.canUndo ?? false
        case #selector(playlistRedo):
            return PlaylistUndoMenuBridge.shared.editor?.canRedo ?? false
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    @objc func toggleQueue() {
        QueuePanelVisibility.toggle()
        // The command's title names what it will do next.
        UIMenuSystem.main.setNeedsRebuild()
    }

    @objc func newPlaylist() {
        Router.main.presentedSheet = .newPlaylist()
    }

    @objc func addToLastPlaylist() {
        let sonosService = SonosService.shared
        let alertService = AlertService.shared

        guard let last = LastPlaylist.current else {
            alertService.showAlert(with: "No Recent Playlist", imageName: "exclamationmark.triangle")
            return
        }

        guard let selectedID = Router.main.selectedID,
              let group = sonosService.sorted.first(where: { $0.coordinatorID == selectedID }) else {
            alertService.showAlert(with: "No Group Selected", imageName: "exclamationmark.triangle")
            return
        }

        let currentTrack = group.coordinatorRoom.track.toPlayable

        Task { @MainActor in
            // Attempt the add and report the real result — the now-playing track's reported service
            // isn't reliable enough to pre-gate on (a Spotify track can surface as a Sonos item).
            guard await last.add(currentTrack) else {
                alertService.showAlert(with: "Couldn’t add to \(last.title)", imageName: "exclamationmark.triangle")
                return
            }
            alertService.showAlertContent(with: currentTrack, subtitle: "Added to \(last.title)", symbolName: "plus")

            // Let tapping the toast open the playlist. Sonos resolves the real playlist for artwork;
            // streaming opens from a lightweight stub (the detail view loads it by id).
            let target: PlayableContent?
            if last.service == .library {
                target = await sonosService.sonosPlaylists().first(where: { $0.id == last.id })
            } else {
                target = last.playableContent
            }
            if let target {
                alertService.alert.handleTap = {
                    Router.main.presentedSheet = .mediaDetail(content: target, group: nil)
                }
            }
        }
    }
}

class CueSceneDelegate: NSObject, UIWindowSceneDelegate {
    var toolbarDelegate = ToolbarDelegate()
    #if targetEnvironment(macCatalyst)
    private var windowSizeObserver: WindowSizeObserver?
    #endif
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
#if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            // A unified toolbar across the top of the window, the way Xcode
            // and Music have one, holding the queue toggle in its trailing
            // corner. No title: the sidebar header names the app.
            let toolbar = NSToolbar(identifier: "com.cue.main")
            toolbar.delegate = toolbarDelegate
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unified
            titlebar.toolbar = toolbar
        }
        
        // Floor only. The old 2000x1500 ceiling stopped the window growing
        // past it on a large display, and there's no reason to cap it — the
        // layout is fluid. The floor is what keeps the sidebar, content and
        // queue panel from squashing each other.
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 920, height: 600)
        
        // Restore saved window frame
        if let savedFrame = WindowFrameStore.savedFrame {
            let geometry = UIWindowScene.GeometryPreferences.Mac(systemFrame: savedFrame)
            windowScene.requestGeometryUpdate(geometry)
        }
        
        // Start observing window size changes
        windowSizeObserver = WindowSizeObserver(windowScene: windowScene)
#endif
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
#if targetEnvironment(macCatalyst)
        windowSizeObserver = nil
#endif
    }
    
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {

        if shortcutItem.type == "com.cue.search" {
            Task { @MainActor in
                // MARK: Delay for Toolbar
                try await Task.sleep(for: .milliseconds(200))
                Router.main.path.removeAll()
                Router.main.presentedSheet = .search()
            }
        }
    }
}

final class ToolbarDelegate: NSObject {
    @objc func prefs(_ sender:Any) {
        Task { @MainActor in
            Router.main.presentedSheet = .settings()
        }
    }

    @objc func search(_ sender:Any) {
        Task { @MainActor in
            Router.main.inspectorSheet = .search()
        }
    }
    
    @objc func sorting(_ sender:Any) {
        Task { @MainActor in
            print("HERE")
        }
    }

    @objc func toggleQueue(_ sender: Any) {
        Task { @MainActor in
            QueuePanelVisibility.toggle()
        }
    }
}

/// The queue panel's stored show/hide flag, for the places outside SwiftUI
/// that flip it: the Mac's toolbar item and its View menu command. The
/// `@AppStorage` readers (`PlayerView`, each tab's panel) pick the change
/// up from `UserDefaults` like any other.
@MainActor
enum QueuePanelVisibility {
    static var isShown: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.queueInspectorVisible)
    }

    static func toggle() {
        UserDefaults.standard.set(!isShown, forKey: AppStorageKeys.queueInspectorVisible)
    }
}

#if targetEnvironment(macCatalyst)
extension NSToolbarItem.Identifier {
    static let preferences = NSToolbarItem.Identifier("com.cue.preferences")
    static let sorting = NSToolbarItem.Identifier("com.cue.sorting")
    static let toggleQueue = NSToolbarItem.Identifier("com.cue.toggleQueue")
//    static let newFolder = NSToolbarItem.Identifier("com.highcaffeinecontent.catalystexample.newfolder")
//    static let search = NSToolbarItem.Identifier("com.cue.search")
}


extension ToolbarDelegate: NSToolbarDelegate {

    func toolbarIdentifiers() -> [NSToolbarItem.Identifier] {
        // Just the queue toggle, pushed to the trailing edge — Xcode's
        // inspector button. No sidebar toggle or tracking separator: the
        // SwiftUI tab sidebar isn't a split-view column AppKit can drive.
        return [.flexibleSpace, .toggleQueue]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarIdentifiers()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarIdentifiers()
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .toggleQueue {
            let barItem = UIBarButtonItem(image: UIImage(systemName: "sidebar.trailing"), style: .plain, target: self, action: #selector(toggleQueue(_:)))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
            item.label = NSLocalizedString("Queue", comment: "")
            item.accessibilityLabel = NSLocalizedString("Show or Hide Queue", comment: "")
            item.toolTip = NSLocalizedString("Show or Hide Queue (⌥⌘0)", comment: "")
            return item
        }
        if itemIdentifier == .preferences {
            let barItem = UIBarButtonItem(image: UIImage(systemName: "switch.2"), style: .plain, target: self, action: #selector(prefs(_:)))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
            item.accessibilityLabel = NSLocalizedString("Preferences", comment: "")
            item.toolTip = NSLocalizedString("Preferences", comment: "")
            return item
        }
//        else if itemIdentifier == .search {
//            let barItem = UIBarButtonItem(image: UIImage(systemName: "sparkle.magnifyingglass"), style: .plain, target: self, action: #selector(search))
//            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
//            item.accessibilityLabel = NSLocalizedString("Search", comment: "")
//            item.toolTip = NSLocalizedString("Search", comment: "")
//            return item
//        }
//        else if itemIdentifier == .newFolder {
//            let barItem = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: nil)
//            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
//            item.accessibilityLabel = NSLocalizedString("TOOLBAR_NEW_FOLDER_BUTTON", comment: "")
//            item.toolTip = NSLocalizedString("TOOLBAR_NEW_FOLDER_BUTTON", comment: "")
//
//            return item
//        }
//        else if itemIdentifier == .search {
//
//            if let searchItem = CATAppDelegate.appKitController?.searchToolbarItem(sceneIdentifier:scene?.session.persistentIdentifier ?? UUID().uuidString, itemIdentifier: itemIdentifier, target: self, selector: #selector(search(_:))) {
//                return searchItem
//            }
////            else {
//                return NSToolbarItem(itemIdentifier: itemIdentifier)
////            }
//        }
//        else {
//            return NSToolbarItem(itemIdentifier: itemIdentifier)
//        }
        
        if itemIdentifier == .sorting {
            let barItem = UIBarButtonItem(image: UIImage(systemName: "switch.2"), style: .plain, target: self, action: #selector(prefs(_:)))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barItem)
            item.accessibilityLabel = NSLocalizedString("Preferences", comment: "")
            item.toolTip = NSLocalizedString("Preferences", comment: "")
            return item
        }
        return NSToolbarItem(itemIdentifier: itemIdentifier)
    }

}
#endif


