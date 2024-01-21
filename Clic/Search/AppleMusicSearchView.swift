import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit
import NukeUI

struct AppleMusicSearchView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @Binding var results: [ItunesResult]
    @Binding var filters: [FilterSelection]
    var group: GroupRoom?

    var body: some View {
        //        if filters.filter(\.isFiltered).isEmpty {
        ForEach(results) { result in
            Button {
                Task {
                    let content = PlayableContent(
                        title: result.trackName,
                        subtitle: result.artistName,
                        artwork: URL(
                            string: result.artworkURL
                        ),
                        content: MediaContent(
                            service: .apple,
                            id: String(
                                result.trackID
                            ),
                            type: .track,
                            location: nil
                        )
                    )
                    playHistory.remove(content)
                    playHistory.insert(content, at: 0)
                    guard let group = group else {
                        let content = PlayableContent(title: result.trackName, subtitle: result.artistName, artwork: URL(string: result.artworkURL), content: MediaContent(service: .apple, id: String(result.trackID), type: .track, location: nil))
                        router.navigate(to: .groupDestination(content: content))
                        return
                    }
                    router.dismiss = true
                    await sonosService.queue(song: "\(result.trackID)", on: group)
                    await sonosService.play(ip: group.coordinatorRoom.ip)
                }
            } label: {
                HStack {
                    LazyImage(url: URL(string: result.artworkURL)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .foregroundStyle(.thinMaterial)
                                .frame(width: 60, height: 60)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text(result.trackName)
                        Text(result.artistName)
                            .foregroundStyle(.secondary)
                    }
                }
                .fontDesign(.rounded)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    Task {
                        guard let group = group else {
                            let content = PlayableContent(title: result.trackName, subtitle: result.artistName, artwork: URL(string: result.artworkURL), content: MediaContent(service: .apple, id: String(result.trackID), type: .track, location: nil))
                            router.navigate(to: .groupDestination(content: content))
                            return
                        }
                        router.dismiss = true
                        await sonosService.queue(song: result.trackID.description, on: group, position: .next)
                    }
                } label: {
                    Label("Play Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
            }
        }
        //        } else {
        //            ForEach(filters.filter(\.isFiltered)) { filter in
        //                Text(filter.filter.title)
        //                //                switch filter.filter {
        //                //                case .albums:
        //                //                    if let albums = spotifyResult?.albums?.items {
        //                //                        albumRow(albums: albums)
        //                //                    }
        //                //                case .artist:
        //                //                    if let albums = spotifyResult?.albums?.items {
        //                //                        albumRow(albums: albums)
        //                //                    }
        //                //                case .tracks:
        //                //                    if let tracks = spotifyResult?.tracks?.items {
        //                //                        trackSection(tracks: tracks)
        //                //                    }
        //                //                case .playlists:
        //                //                    if let albums = spotifyResult?.albums?.items {
        //                //                        albumRow(albums: albums)
        //                //                    }
        //                //                }
        //            }
        //            .animation(.bouncy, value: filters)
        //        }
    }
}
//
//#Preview {
//    Text("Searching...")
//        .sheet(isPresented: .constant(true)) {
//            ImprovedSearch(query: "Dua Lipa", group: .garage)
//                .environment(SonosService())
//        }
//}
//
//#Preview("Empty Queue") {
//    Text("Searching Empty...")
//        .sheet(isPresented: .constant(true)) {
//            ImprovedSearch(query: "", group: .garage)
//                .environment(SonosService())
//        }
//}
//
//#Preview("Full Screen") {
//    Text("Searching Empty...")
//        .fullScreenCover(isPresented: .constant(true)) {
//            ImprovedSearch(query: "", group: .garage)
//                .environment(SonosService())
//        }
//}

