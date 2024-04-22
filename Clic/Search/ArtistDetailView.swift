import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct ArtistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @State var playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var albums: [PlayableContent] = []

    @State private var artworkURL: URL?

    var group: GroupRoom?

    var body: some View {
        List {
            LazyImage(url: artworkURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if state.isLoading {
                    RoundedRectangle(cornerRadius: 4)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.ultraThinMaterial)
                        .shadow(radius: 2)
                }
            }
            .clipShape(Circle())
            .shadow(radius: 2)
            .scaledToFit()
            .frame(width: 200, height: 200)
            .frame(maxWidth: .infinity)
            .listSectionSeparator(.hidden)

            Section("Top Tracks") {
                ForEach(tracks) { track in
                   PlayableContentView(item: track, group: group)
                }
                if tracks.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                }
            }

            Section("Albums") {
                ForEach(albums) { album in
                    PlayableContentView(item: album, group: group)
                }
                if tracks.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                }
            }

//            Section {
//                ForEach(tracks) { track in
//                   PlayableContentView(item: track, group: group)
//                }
//                if tracks.isEmpty {
//                    ProgressView()
//                        .frame(maxWidth: .infinity, alignment: .center)
//                        .listRowSeparator(.hidden)
//                }
//                ForEach(albums) { album in
//                    PlayableContentView(item: album, group: group)
//                }
//                if tracks.isEmpty {
//                    ProgressView()
//                        .frame(maxWidth: .infinity, alignment: .center)
//                        .listRowSeparator(.hidden)
//                }
//            } header: {
// MARK: Add back when queue multiple songs
//                Button {
//                    play(content: playableContent)
//                } label: {
//                    Text("Play Artist Top Tracks")
//                }
//                .padding()
//                .background(
//                    .ultraThinMaterial,
//                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
//                )
//                .padding(.vertical)
//                .frame(maxWidth: .infinity, alignment: .center)
//            }
        }
        .listStyle(.inset)
        .listSectionSeparator(.hidden)
        .navigationTitle(playableContent.title)
        .headerProminence(.increased)
        .animation(.spring, value: artworkURL)
        .task {
            artworkURL = playableContent.artwork
            switch (playableContent.content.type, playableContent.content.service) {
            case (.artist, .apple):
                guard let artist: Artist = try? await MusicSearchService().lookup(id: playableContent.content.id) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                artworkURL = artist.artwork?.url(width: 500, height: 500)
            case (.artist, .spotify):
                async let artist = MusicSearchService().spotifyArtist(id: playableContent.content.id)
                async let artistAlbums = MusicSearchService().spotifyArtistAlbums(id: playableContent.content.id)
                async let artistTopTracks = MusicSearchService().spotifyArtistTopTracks(id: playableContent.content.id)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                self.tracks = artistTopTracksAwait.map(\.toPlayable)
//                print(artistAwait)
//                print(artistAlbumsAwait)

            default:
                break
            }
        }
    }

    private func play(content: PlayableContent, position: QueuePosition = .now) {
        Task {
            guard let group = group else {
                router.navigate(to: .groupDestination(content: content))
                return
            }

            playHistory.remove(content)
            playHistory.insert(content, at: 0)

            router.dismiss = true
            await sonosService.queue(content: content.content, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
    }
}

#Preview {
    // https://music.apple.com/us/playlist/dua-lipa-essentials/pl.ee7b1aea4b5f42d398e6cd3084f7396b
    // https://music.apple.com/us/album/future-nostalgia-the-moonlight-edition/1551178998
    /// 6M2wZ9GZgrQXHCFfjv46we

    NavigationStack {
        ArtistDetailView(playableContent: PlayableContent(
            title: "Dua Lipa",
            subtitle: "",
            artwork: nil,
            content: MediaContent(
                service: .spotify,
                id: "6M2wZ9GZgrQXHCFfjv46we",
                type: .artist,
                location: nil
            ))
        )
        .environment(SonosService.shared)
        .environment(Router())
    }
}
