import CloudStorage
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit
import Kingfisher

struct AppleMusicSearchView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Binding var results: [ItunesResult]
    @Binding var filters: [FilterSelection]
    var group: GroupRoom

    var body: some View {
//        if filters.filter(\.isFiltered).isEmpty {
            ForEach(results) { result in
                Button {
                    dismiss()
                    Task {
                        await sonosService.queue(song: "\(result.trackID)", on: group)
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    HStack {
                        AsyncImage( url: URL(string: result.artworkURL),
                                    transaction: Transaction(animation: .snappy)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .frame(width: 60, height: 60)
                            default:
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
                        dismiss()
                        Task {
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

#Preview {
    Text("Searching...")
        .sheet(isPresented: .constant(true)) {
            ImprovedSearch(query: "Dua Lipa", group: .garage)
                .environment(SonosService())
        }
}

#Preview("Empty Queue") {
    Text("Searching Empty...")
        .sheet(isPresented: .constant(true)) {
            ImprovedSearch(query: "", group: .garage)
                .environment(SonosService())
        }
}

#Preview("Full Screen") {
    Text("Searching Empty...")
        .fullScreenCover(isPresented: .constant(true)) {
            ImprovedSearch(query: "", group: .garage)
                .environment(SonosService())
        }
}

