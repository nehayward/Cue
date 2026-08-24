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
        if !sonosService.favorites.isEmpty {
            // Same Section structure as ApplePlaylistsView — bare rows get
            // different insets than sectioned ones in the search list, which
            // left the two headers visibly misaligned.
            Section {
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
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .listRowSeparator(.hidden)

                ForEach(sonosService.favorites.prefix(5)) { item in
                    PlayableContentView(item: item)
                }
            }
        }
    }
}
