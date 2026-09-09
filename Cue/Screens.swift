//
//  Screens.swift
//  Cue
//
//  Created by Nick Hayward on 8/25/26.
//
import Defaults
import MusicSearchKit
import SwiftUI

@MainActor
enum Screens {

    @ViewBuilder
    static var home: some View {
        let selectedGroupService = SelectedGroupService(group: nil)

        HomeScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
            .withQueuePanel()
    }
    
    @ViewBuilder
    static var search: some View {
        let searchRouter = Router.search
        let selectedGroupService = SelectedGroupService(group: nil)
        SearchScreen(favorites: true)
            // The TabView is tinted `.primary` so its sidebar selection reads
            // that way; tab content wants the app's real accent back.
            .tint(Color("Accent"))
            .environment(searchRouter)
            .environment(selectedGroupService)
            .onDisappear {
                Router.search.path.removeAll()
                Router.search.presentedSheet = nil
            }
            .withQueuePanel()
    }
    
    @ViewBuilder
    static var browse: some View {
        let selectedGroupService = SelectedGroupService(group: nil)
        
        BrowseScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
            .withQueuePanel()
        
    }

    /// The Radio tab: stations from every source, and a search over them.
    @ViewBuilder
    static var radio: some View {
        let selectedGroupService = SelectedGroupService(group: nil)

        RadioScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }

    /// A provider's own tab — its library's front page, listing the
    /// collections its sidebar section is showing.
    @ViewBuilder
    static func providerRoot(_ service: MediaSearchService, collections: [ProviderCollection]) -> some View {
        let selectedGroupService = SelectedGroupService(group: nil)

        ProviderTabScreen(service: service, collections: collections)
            .tint(Color("Accent"))
            .environment(selectedGroupService)
            .withQueuePanel()
    }

    /// One collection of a provider — a tab in its sidebar section.
    @ViewBuilder
    static func providerCollection(_ service: MediaSearchService, collections: [ProviderCollection], collection: ProviderCollection) -> some View {
        let selectedGroupService = SelectedGroupService(group: nil)

        ProviderTabScreen(service: service, collections: collections, collection: collection)
            .tint(Color("Accent"))
            .environment(selectedGroupService)
            .withQueuePanel()
    }
}

/// The trailing Next Up panel, applied to each tab's content rather than
/// around the `TabView`: the sidebar then keeps the window's full width to
/// decide whether it sits beside the content or overlays it, and only the
/// content column gives way to the panel.
///
/// Hidden at compact widths rather than a sheet: on iPhone the queue is the
/// player's, and a sheet here would fight the one it presents (they share
/// the stored flag).
private struct TabQueuePanel: ViewModifier {
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var showQueue: Bool = false

    func body(content: Content) -> some View {
        content.queuePanel(isPresented: $showQueue, compact: .hidden, showsToggle: true) { QueueNextUpView() }
    }
}

extension View {
    func withQueuePanel() -> some View {
        modifier(TabQueuePanel())
    }
}
