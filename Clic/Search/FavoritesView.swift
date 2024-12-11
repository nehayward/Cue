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
                NavigationLink {
                    List {
                        ForEach(sonosService.favorites) { item in
                            PlayableContentView(item: item)
                        }
                    }
                    .contentMargins(.bottom, 120, for: .scrollContent)
                    .navigationTitle("Sonos Favorites")
                    .miniPlayerOnScrollHandler()
                } label: {
                    Text("Sonos Favorites")
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)
                        .bold()
                }
                .listRowSeparator(.hidden)

                ForEach(sonosService.favorites.prefix(5)) { item in
                    PlayableContentView(item: item)
                }
            }
        }
        .task {
            await sonosService.getFavoriteList()
        }
    }
}
