//
//  Screens.swift
//  Cue
//
//  Created by Nick Hayward on 8/25/26.
//
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
    }
    
    @ViewBuilder
    static var browse: some View {
        let selectedGroupService = SelectedGroupService(group: nil)
        
        BrowseScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
        
    }

    /// A provider's own tab — its library's front page, listing the
    /// collections switched on for it.
    @ViewBuilder
    static func providerRoot(_ provider: TabProvider) -> some View {
        let selectedGroupService = SelectedGroupService(group: nil)

        ProviderTabScreen(service: provider.service, collections: provider.collections)
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }

    /// One collection of a provider — a tab in its sidebar section.
    @ViewBuilder
    static func providerCollection(_ provider: TabProvider, _ collection: ProviderCollection) -> some View {
        let selectedGroupService = SelectedGroupService(group: nil)

        ProviderTabScreen(service: provider.service, collections: provider.collections, collection: collection)
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }
}
