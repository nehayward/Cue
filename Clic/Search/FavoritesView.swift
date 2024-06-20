import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import SwiftUI

struct FavoritesView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    var body: some View {
        Group {
            if let favorites = sonosService.favorites, !favorites.items.isEmpty {
                Text("Favorites")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .fontDesign(.rounded)
                    .bold()
                ForEach(favorites.items.prefix(10)) { item in
                    PlayableContentView(item: item.toPlayable)
                }

                NavigationLink {
                    List {
                        ForEach(favorites.items) { item in
                            PlayableContentView(item: item.toPlayable)
                        }
                    }
                    .contentMargins(.bottom, 80, for: .scrollContent)
                    .navigationTitle("Favorites")
                } label: {
                    Text("Show All")
                }
                .listRowSeparator(.hidden)
            }
        }
        .task {
            await sonosService.getFavoriteList()
        }
    }
}
