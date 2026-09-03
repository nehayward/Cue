//
//  Screens.swift
//  Aux
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
        // The field lives above the TabView so it survives a tab switch;
        // this instance must not draw a second one.
        SearchScreen(favorites: true, showsSearchField: false)
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
