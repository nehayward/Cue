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
    @Environment(GroupRoom.self) var group: GroupRoom?

    var body: some View {
        Group {
            if let favorites = sonosService.favorites, !favorites.items.isEmpty {
                Section {
                    ForEach(favorites.items) { item in
                        PlayableContentView(item: item.toPlayable, group: group)
                    }
                } header: {
                    Label {
                        Text("Favorites")
                    } icon: {
                        Image(systemName: "text.badge.star")
                    }
                }
            }
        }
        .task {
            await sonosService.getFavoriteList()
        }
    }
}
