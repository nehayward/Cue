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
        SearchScreen(favorites: true)
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
            .environment(selectedGroupService)
        
    }
}
