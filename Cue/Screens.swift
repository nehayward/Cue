//
//  Screens.swift
//  Cue
//
//  Created by Nick Hayward on 8/25/26.
//
import SwiftUI

@MainActor
enum Screens {
    
    @ViewBuilder
    static var search: some View {
        let searchRouter = Router.search
        let selectedGroupService = SelectedGroupService(group: nil)
        // Draws its own `.searchable`. `GlobalSearchField` (the field hosted
        // above the TabView, which survives a tab switch) is commented out in
        // `CueApp`, so without this there is no search field at all — flip this
        // back to `false` if that one is re-enabled, or you get two.
        SearchScreen(favorites: true, showsSearchField: true)
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
}
