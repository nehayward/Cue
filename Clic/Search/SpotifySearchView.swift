import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct SpotifySearchView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Environment(Router.self) var router: Router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    var isAdding: Bool = false
    @Binding var addingContent: PlayableContent?
    @Binding var spotifyResult: SpotifyResult?
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        if filters.filter(\.isFiltered).isEmpty {
            Group {
                if let artists = spotifyResult?.artists?.items {
                    artistRow(artists: artists)
                }

                if let playlists = spotifyResult?.playlists?.items {
                    playlist(playlists: playlists)
                }
                if let tracks = spotifyResult?.tracks?.items {
                    trackSection(tracks: tracks)
                }

                if let albums = spotifyResult?.albums?.items {
                    albumRow(albums: albums)
                }
            }
            .fontDesign(.rounded)
        } else {
            ForEach(filters.filter(\.isFiltered)) { filter in
                switch filter.filter {
                case .albums:
                    if let albums = spotifyResult?.albums?.items {
                        albumRow(albums: albums)
                    }
                case .artist:
                    if let artists = spotifyResult?.artists?.items {
                        artistRow(artists: artists)
                    }
                case .songs:
                    if let tracks = spotifyResult?.tracks?.items {
                        trackSection(tracks: tracks)
                    }
                case .playlists:
                    if let playlists = spotifyResult?.playlists?.items {
                        playlist(playlists: playlists)
                    }
                }
            }
            .animation(.bouncy, value: filters)
            .fontDesign(.rounded)
        }
    }

    private func trackSection(tracks: [SpotifyTrackItem]) -> some View {
        Section {
            ForEach(tracks) { item in
                PlayableContentView(item: item.toPlayable, group: group)
            }
        } header: {
            Text("Tracks")
        }
    }

    private func albumRow(albums: [SpotifyAlbumItem]) -> some View {
        Section {
            ForEach(albums) { album in
                PlayableContentView(item: album.toPlayable, group: group)
            }
        } header: {
            Text("Albums")
        }
    }

    private func playlist(playlists: [SpotifyPlaylistItems]) -> some View {
        Section {
            ForEach(playlists) { item in
                PlayableContentView(item: item.toPlayable, group: group)
            }
        } header: {
            Text("Playlist")
        }
    }

    private func artistRow(artists: [SpotifyArtistsItems]) -> some View {
        Section {
            ForEach(artists) { item in
                PlayableContentView(item: item.toPlayable, group: group)
            }
        } header: {
            Text("Artists")
        }
//        Section {
//            ScrollView(.horizontal) {
//                HStack {
//                    ForEach(artists) { item in
//                        VStack {
//                            AsyncImage( url: URL(string: item.images.first?.url ?? ""),
//                                        transaction: Transaction(animation: .snappy)
//                            ) { phase in
//                                switch phase {
//                                case .success(let image):
//                                    image
//                                        .resizable()
//                                        .frame(width: 60, height: 60)
//                                        .clipShape(Circle())
//                                default:
//                                    RoundedRectangle(cornerRadius: 12)
//                                        .foregroundStyle(.thinMaterial)
//                                        .frame(width: 60, height: 60)
//                                }
//                            }
//                            VStack(alignment: .leading) {
//                                Text(item.name)
//                            }
//                        }
//                        .fontDesign(.rounded)
//                        .onTapGesture {
//                            dismiss()
//                            Task {
//                                guard let group = group else { return }
//                                await sonosService.queueSpotifyArtistTopTracks(id: item.id, group: group)
//                                await sonosService.play(ip: group.coordinatorRoom.ip)
//                            }
//                        }
//                    }
//                }
//            }
//            .scrollIndicators(.hidden)
//        } header: {
//            Text("Artist")
//        }
    }
}

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

