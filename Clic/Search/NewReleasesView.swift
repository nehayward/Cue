import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import MusicSearchKit
import SwiftUI

struct NewReleasesView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(GroupRoom.self) var group: GroupRoom?
    @Environment(MusicSearchService.self) var musicSearchService

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(musicSearchService.newReleases) { album in
                        NavigationLink(value: RouterDestination.mediaDetail(content: album.toPlayable, group: group)) {
                            VStack {
                                LazyImage(url: album.images.biggestImageURL) { state in
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .frame(width: 120, height: 120)
                                Text(album.name)
                                    .tint(.primary)
                                    .fontDesign(.rounded)
                                    .lineLimit(2, reservesSpace: true)
                                    .frame(width: 120)
                            }
                        }
                    }
                    .environment(router)
                    .environment(group)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .mask(
                HStack(spacing: 0) {
                    // Left gradient
                    LinearGradient(gradient:
                                    Gradient(
                                        colors: [Color.black.opacity(0), Color.black]),
                                   startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 20)

                    // Middle
                    Rectangle().fill(Color.black)

                    // Right gradient
                    LinearGradient(gradient:
                                    Gradient(
                                        colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 20)
                }
            )
            .overlay(alignment: .center) {
                if musicSearchService.newReleases.isEmpty {
                    ProgressView()
                        .frame(height: 120)
                }
            }
        } header: {
            Text("New Releases")
        }
        .task {
            if let albums = await musicSearchService.spotifyNewReleases()?.albums {
                musicSearchService.newReleases = albums.items
            }
        }
    }
}
