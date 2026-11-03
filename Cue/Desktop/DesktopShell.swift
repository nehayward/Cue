import MusicSearchKit
import SonosKit
import SwiftUI

/// What the Mac window shows besides the tabs: a playlist chosen in the
/// sidebar, which takes the content's place until a tab is chosen again.
@MainActor
@Observable
final class DesktopState {
    static let shared = DesktopState()

    /// The playlist on show, or nil for the selected tab's page.
    private(set) var playlist: PlayableContent?

    private init() {}

    /// The stack on screen, where a sidebar playlist's menu presents its
    /// sheets.
    var currentRouter: Router {
        if playlist != nil { return .desktopPlaylist }
        return Router.forTab(AppState.shared.resolvedTab(Router.main.selectedTab))
    }

    /// Shows a tab. Chosen again while it shows, it goes back to its first
    /// page, as a tab bar's tab does. Search puts the cursor in its field
    /// either way.
    func select(_ tab: AppTab) {
        let wasShowing = playlist == nil && AppState.shared.resolvedTab(Router.main.selectedTab) == tab
        if playlist != nil {
            playlist = nil
        }
        if wasShowing {
            Router.main.handleReselection(of: tab)
            Router.forTab(tab).path.removeAll()
        } else {
            if Router.main.selectedTab != tab {
                Router.main.selectedTab = tab
            }
            if tab == .search {
                SearchActivator.shared.requestFocus()
            }
        }
    }

    /// Shows a playlist's page in the content's place.
    func open(_ playlist: PlayableContent) {
        guard self.playlist?.id != playlist.id else {
            Router.desktopPlaylist.path.removeAll()
            return
        }
        Router.desktopPlaylist.path.removeAll()
        self.playlist = playlist
    }

    func isShowing(_ tab: AppTab) -> Bool {
        playlist == nil && AppState.shared.resolvedTab(Router.main.selectedTab) == tab
    }

    func isShowing(_ playlist: PlayableContent) -> Bool {
        self.playlist?.id == playlist.id
    }
}

/// The Mac's window, in place of the `TabView` (`AppState.usesDesktopShell`):
/// laid out as macOS 27's Music is. The sidebar runs the window's full
/// height down the leading side, the traffic lights in its corner (the
/// tabs with Search, the library's collections, its playlists), the queue
/// the same down the trailing side, and the page between them. Both
/// panels are clear over macOS's own sidebar material, which sits behind
/// the whole window (`WindowMaterial`), so the desktop shows through them
/// as through Music's; the page draws its own background over it.
struct DesktopShell: View {
    @State private var appState = AppState.shared
    /// Whether the window has room for the queue. A flag rather than the
    /// width, so a resize runs this again only as it crosses the line.
    @State private var isWide = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openWindow) private var openWindow

    /// A base measure at the window's size (`InterfaceSize`).
    private func scaled(_ value: CGFloat) -> CGFloat {
        (value * DesktopStyle.scale(typeSize)).rounded()
    }

    var body: some View {
        let queueWidth = scaled(min(max(CGFloat(appState.queuePanelWidth), 280), 400))
        let showsQueue = appState.showsQueuePanel && isWide

        HStack(spacing: 0) {
            DesktopSidebar()
                .frame(width: scaled(DesktopStyle.sidebarWidth))
                .desktopPanelEdge(.trailing)

            DesktopContent()

            if showsQueue {
                DesktopQueuePanel()
                    .frame(width: queueWidth)
                    .desktopPanelEdge(.leading)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showsQueue)
        // No band under the title bar: the lists' edge effect drew one over
        // the material and the page.
        .scrollEdgeEffectHidden26()
        .ignoresSafeArea()
        .onGeometryChange(for: Bool.self) { [threshold = scaled(DesktopStyle.queueMinWindowWidth)] in $0.size.width >= threshold } action: { isWide = $0 }
#if targetEnvironment(macCatalyst)
        .onAppear {
            // How Settings opens its window from outside a view (the menu
            // bar, the routers).
            SettingsWindow.shared.openWindow = openWindow
            WindowMaterial.install()
        }
#endif
    }
}

/// The window between the sidebar and the queue: the page, running to the
/// window's top and bottom edges with the player's bar floating over its
/// foot (`DesktopPlayerBar`).
///
/// Each tab's page is kept once it has been shown, hidden while another
/// shows, as a `TabView` keeps its tabs: built again on every switch, each
/// page ran its first load again, its spinner and all, and lost its place.
struct DesktopContent: View {
    @State private var appState = AppState.shared
    @State private var desktop = DesktopState.shared
    /// The tabs whose pages are alive, the latest shown last.
    @State private var keptTabs: [AppTab] = []
    @Environment(\.dynamicTypeSize) private var typeSize

    private var router: Router { .main }

    /// A base measure at the window's size (`InterfaceSize`).
    private func scaled(_ value: CGFloat) -> CGFloat {
        (value * DesktopStyle.scale(typeSize)).rounded()
    }

    /// Pages kept besides the one showing: Browse, Search and a few more.
    private static let keptTabLimit = 6

    var body: some View {
        let selected = appState.resolvedTab(router.selectedTab)

        VStack(spacing: 0) {
            // Up to the window's top and bottom edges, as Music's pages
            // run: an artist's picture fills the top of the window, and the
            // player's bar floats over the foot, the page scrolling under
            // it. A margin, not a safe-area inset, ends a list above the
            // bar: an inset laid the pages out above it instead, cut off at
            // its top edge.
            pages(selected: selected)
                .contentMargins(.bottom, scaled(DesktopStyle.barHeight + DesktopStyle.barMargin * 2))
                .overlay(alignment: .bottom) {
                    DesktopPlayerBar()
                        .frame(height: scaled(DesktopStyle.barHeight))
                        .padding([.horizontal, .bottom], scaled(DesktopStyle.barMargin))
                }
                .frame(maxWidth: .infinity)
        }
        // No band under the title bar: the lists' edge effect drew one, with
        // a hairline, across the page and the panels.
        .scrollEdgeEffectHidden26()
        .background(DesktopStyle.windowBackground)
        .ignoresSafeArea(.container, edges: .vertical)
        .onChange(of: selected, initial: true) { _, tab in
            keep(tab)
        }
    }

    /// Every kept page, the selected one on top, or the playlist chosen in
    /// the sidebar over them all.
    ///
    /// In an overlay, so the hidden pages' frozen sizes (`KeptPageFrame`)
    /// never size the column.
    private func pages(selected: AppTab) -> some View {
        // Through the title bar's inset: a colour keeps to the safe area
        // by itself, and the clip to it ended the pages short of the
        // window's top. The pages still read the inset, so their bars keep
        // below the title bar.
        Color.clear
            .ignoresSafeArea(.container, edges: .vertical)
            .overlay(alignment: .topLeading) {
                pageStack(selected: selected)
            }
            .clipped()
    }

    private func pageStack(selected: AppTab) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(keptTabs, id: \.self) { tab in
                let isShown = desktop.playlist == nil && tab == selected
                page(for: tab)
                    .modifier(KeptPageFrame(isShown: isShown))
                    .opacity(isShown ? 1 : 0)
                    .allowsHitTesting(isShown)
                    // Off too, so a hidden page's keyboard shortcuts (Escape
                    // on Browse) don't answer for the one on show.
                    .disabled(!isShown)
                    .accessibilityHidden(!isShown)
            }
            if let playlist = desktop.playlist {
                Screens.desktopPlaylist(playlist)
                    .id(playlist.id)
            }
        }
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            Screens.home
        case .search:
            Screens.search
        case .browse:
            Screens.browse
        case .radio:
            Screens.radio
        case .audiobooks:
            Screens.audiobooks
        case .downloads:
            Screens.downloads
        case let .provider(service):
            Screens.providerRoot(service, collections: appState.shownCollections(of: service))
        case let .providerCollection(service, collection):
            Screens.providerCollection(service, collections: appState.shownCollections(of: service), collection: collection)
        }
    }

    /// Keeps `tab`'s page alive, letting the longest unseen go past the
    /// limit. Written only when it changes.
    private func keep(_ tab: AppTab) {
        var tabs = keptTabs.filter { $0 != tab && appState.availableTabs.contains($0) }
        tabs.append(tab)
        while tabs.count > Self.keptTabLimit {
            tabs.removeFirst()
        }
        if tabs != keptTabs {
            keptTabs = tabs
        }
    }
}

/// A kept page's frame: all the room there is while it shows; hidden, the
/// size it last showed at, so a window being resized lays out the page on
/// show alone, as a `TabView` doesn't lay out its tabs off screen. Shown
/// again, it takes the room there is now, once.
private struct KeptPageFrame: ViewModifier {
    let isShown: Bool
    @State private var lastSize: CGSize?

    func body(content: Content) -> some View {
        let frozen = isShown ? nil : lastSize

        content
            .frame(width: frozen?.width, height: frozen?.height)
            .frame(maxWidth: frozen == nil ? .infinity : nil, maxHeight: frozen == nil ? .infinity : nil, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if isShown {
                    lastSize = size
                }
            }
    }
}

/// Next Up, or a book's chapters, down the window's trailing side, up to
/// the window's top as Music's queue is: no traffic lights sit over it.
/// Clear, over the window's material (`WindowMaterial`).
struct DesktopQueuePanel: View {
    var body: some View {
        QueueNextUpView()
            .scrollContentBackground(.hidden)
            .padding(.top, 10)
            .catchesClicks()
            .ignoresSafeArea(.container, edges: .top)
    }
}

/// A playlist chosen in the sidebar: its page as the root of a stack of its
/// own (`Router.desktopPlaylist`), what's opened from it pushed there.
struct DesktopPlaylistScreen: View {
    let playlist: PlayableContent

    @State private var router = Router.desktopPlaylist

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            RouterDestinationView(destination: .mediaDetail(content: playlist, group: nil))
                .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }
}
