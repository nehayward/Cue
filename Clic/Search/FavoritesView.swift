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
            if !sonosService.favorites.isEmpty {
                Text("Favorites")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .fontDesign(.rounded)
                    .bold()
                ForEach(sonosService.favorites.prefix(5)) { item in
                    PlayableContentView(item: item)
                }

                NavigationLink {
                    List {
                        ForEach(sonosService.favorites) { item in
                            PlayableContentView(item: item)
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
