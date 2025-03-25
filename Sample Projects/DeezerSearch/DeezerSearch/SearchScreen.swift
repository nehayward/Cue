//
//  ContentView.swift
//  DeezerSearch
//
//  Created by Nick Hayward on 8/25/24.
//

import SwiftUI

struct SearchScreen: View {
    @State var viewModel = DeezerSearchViewModel(deezerSearchService: .init())
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.results, id: \.id) { result in
                    Text(result.title)
                    AsyncImage(url: result.album.cover)
                }
            }.task(id: viewModel.query) {
                viewModel.search(for: viewModel.query)
            }.overlay {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }.searchable(text: $viewModel.query, isPresented: .constant(true))
        }
    }
    
}

#Preview {
    SearchScreen()
}
