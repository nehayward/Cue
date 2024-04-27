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
                        Button {
                            Task {
                                guard let group = group else {
                                    let content = PlayableContent(
                                        title: item.name,
                                        subtitle: item.description,
                                        artwork: sonosService.favoriteImageURL(on: group, favorite: item),
                                        content: .init(
                                            service: .unknown,
                                            id: item.id,
                                            type: .favorite,
                                            location: nil
                                        )
                                    )
                                    router.navigate(to: .groupDestination(content: content))
                                    return
                                }
                                router.dismiss = true
                                await sonosService.playFavorite(on: group, favoriteID: item.id)
                            }
                        } label: {
                            HStack {
                                let content = PlayableContent(
                                    title: item.name,
                                    subtitle: item.description,
                                    artwork: sonosService.favoriteImageURL(
                                        on: group,
                                        favorite: item
                                    ),
                                    content: .init(
                                        service: .unknown,
                                        id: item.id,
                                        type: .favorite,
                                        location: nil
                                    )
                                )
                                ContentArtworkView(content: .constant(content), artworkURL: sonosService.favoriteImageURL(on: group, favorite: item))
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.description)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button {
                                Task {
                                    await sonosService.deleteFavorite(on: group, favoriteID: item.id)
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .foregroundStyle(.white)
                            }
                            .tint(.red)
                        }
                        .contentShape(.contextMenuPreview, Capsule())
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                Task {
                                    await sonosService.deleteFavorite(on: group, favoriteID: item.id)
                                }
                            }
                        }
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
