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

    /// The stack on screen, which the toolbar's Back and Forward step
    /// through.
    var currentRouter: Router {
        if playlist != nil { return .desktopPlaylist }
        return Router.forTab(AppState.shared.resolvedTab(Router.main.selectedTab))
    }

    /// Shows a tab. Chosen again while it shows, it goes back to its first
    /// page, as a tab bar's tab does; Search's asks for the field.
    func select(_ tab: AppTab) {
        let wasShowing = playlist == nil && AppState.shared.resolvedTab(Router.main.selectedTab) == tab
        if playlist != nil {
            playlist = nil
        }
        if wasShowing {
            Router.main.handleReselection(of: tab)
            Router.forTab(tab).path.removeAll()
        } else if Router.main.selectedTab != tab {
            Router.main.selectedTab = tab
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

/// The Mac's window, in place of the `TabView` (`AppState.usesDesktopShell`),
/// after DaftMusic: rounded cards on the window's background. The sidebar
/// card down the leading side (the tabs, the library's collections, its
/// playlists), Back, Forward and the search field above the page, the
/// queue's card down the trailing side, and the player's cards along the
/// bottom (`DesktopPlayerBar`), the now playing card under the sidebar and
/// the queue's summary under the queue.
///
/// Each tab's page is kept once it has been shown, hidden while another
/// shows, as a `TabView` keeps its tabs: built again on every switch, each
/// page ran its first load again, its spinner and all, and lost its place.
struct DesktopShell: View {
    @State private var appState = AppState.shared
    @State private var desktop = DesktopState.shared
    @State private var desktopRouter = Router.desktop
    /// The tabs whose pages are alive, the latest shown last.
    @State private var keptTabs: [AppTab] = []
    /// Whether the window has room for the queue's card and summary. A
    /// flag rather than the width, so a resize runs this again only as it
    /// crosses the line.
    @State private var isWide = true

    private var router: Router { .main }

    /// Pages kept besides the one showing: Browse, Search and a few more.
    private static let keptTabLimit = 6

    private var queueWidth: CGFloat {
        min(max(CGFloat(appState.queuePanelWidth), 280), 400)
    }

    /// The queue's card, while it's asked for and the window has room.
    private var showsQueueCard: Bool {
        appState.showsQueuePanel && isWide
    }

    /// The queue's summary under it, while the window has room for both
    /// ends of the bar.
    private var showsQueueSummary: Bool { isWide }

    var body: some View {
        @Bindable var desktopRouter = desktopRouter
        let selected = appState.resolvedTab(router.selectedTab)

        VStack(spacing: DesktopStyle.gap) {
            HStack(spacing: DesktopStyle.gap) {
                DesktopSidebar()
                    .frame(width: DesktopStyle.sidebarWidth)

                VStack(spacing: 8) {
                    DesktopToolbar()
                        .frame(height: DesktopStyle.toolbarHeight)
                    pages(selected: selected)
                        .clipShape(.rect(cornerRadius: DesktopStyle.cornerRadius))
                }
                .frame(maxWidth: .infinity)

                if showsQueueCard {
                    DesktopQueueCard()
                        .frame(width: queueWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showsQueueCard)

            DesktopPlayerBar(
                sidebarWidth: DesktopStyle.sidebarWidth,
                queueWidth: queueWidth,
                showsQueueSummary: showsQueueSummary
            )
            .frame(height: DesktopStyle.barHeight)
        }
        .padding(.horizontal, DesktopStyle.gap)
        .padding(.bottom, DesktopStyle.gap)
        .padding(.top, DesktopStyle.topInset)
        .background(DesktopStyle.windowBackground)
        .ignoresSafeArea()
        .onGeometryChange(for: Bool.self) { $0.size.width >= DesktopStyle.queueMinWindowWidth } action: { isWide = $0 }
        .onChange(of: selected, initial: true) { _, tab in
            keep(tab)
        }
        // Settings, from the sidebar's gear.
        .withSheetDestinations(sheetDestinations: $desktopRouter.presentedSheet)
    }

    /// Every kept page, the selected one on top, or the playlist chosen in
    /// the sidebar over them all.
    private func pages(selected: AppTab) -> some View {
        ZStack {
            ForEach(keptTabs, id: \.self) { tab in
                let isShown = desktop.playlist == nil && tab == selected
                page(for: tab)
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

/// Next Up, or a book's chapters, as the window's trailing card.
struct DesktopQueueCard: View {
    var body: some View {
        QueueNextUpView()
            .scrollContentBackground(.hidden)
            .background(DesktopStyle.card)
            .clipShape(.rect(cornerRadius: DesktopStyle.cornerRadius))
    }
}

/// A playlist chosen in the sidebar: its page as the root of a stack of its
/// own (`Router.desktopPlaylist`), so Back and Forward step through what's
/// opened from it.
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
