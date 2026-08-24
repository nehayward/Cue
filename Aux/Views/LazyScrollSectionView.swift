import Analytics
import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

// MARK: TODO
struct LazyScrollSectionView: View {
    let items: [PlayableContent]
    
    var body: some View {
        if !items.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach(items.prefix(10)) { item in
                            VStack {
                                PlayableArtworkView(item: item)
                                Text(item.title)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .lineLimit(1, reservesSpace: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fontDesign(.rounded)
                            }
                            .containerRelativeFrame(.horizontal, alignment: .topLeading) { length, axis in
                                axis == .vertical ? length / 3.0 : length / 2.5
                            }
                            .draggable(item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
//                NavigationLink(
//                    value: RouterDestination.playableList(
//                        title: "Spotify Songs",
//                        action: { offset in
//                            await spotifyBrowseService.updateSongs()
//                            return Array(spotifyBrowseService.tracks)
//                        }
//                    )
//                ) {
                    HStack(spacing: 2) {
                        Text("Liked Songs")
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
//                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        LazyVStack {
            LazyScrollSectionView(items: .debugSamples)
        }
    }
    .withEnvironments()
}
#endif
