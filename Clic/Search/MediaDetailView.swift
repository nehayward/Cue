import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @State var playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var artworkURL: URL?

    var group: GroupRoom?

    var body: some View {
        List {
            Group {
                LazyImage(url: artworkURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if state.isLoading {
                        RoundedRectangle(cornerRadius: 4)
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.ultraThinMaterial)
                            .shadow(radius: 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .scaledToFit()
                .frame(width: 300, height: 300)
            }
            .frame(maxWidth: .infinity)
            .listSectionSeparator(.hidden)
            .listRowBackground(Color.clear)
            Section {
                ForEach(tracks) { track in
                    Button {
                        play(content: track)
                    } label: {
                        HStack {
                            if playableContent.content.type == .playlist {
                                ContentArtworkView(content: .constant(track))
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                            }
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(track.title)
                                    Spacer()
                                }
                                Text(track.subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let duration = track.duration {
                                Text(duration, format: .time(pattern: .minuteSecond))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Menu {
                                menu(content: track)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(maxWidth: 40, maxHeight: .infinity)
                                    .background(.clear)
                            }
                        }
                        .contextMenu {
                            menu(content: track)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if tracks.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } header: {
                Button {
                    switch playableContent.content.type {
                    case .album:
                        play(content: playableContent)
                    case .playlist:
                        play(content: playableContent)
                    default:
                        break
                    }
                } label: {
                    Text("Queue All")
                }
                .padding()
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .padding(.vertical)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.inset)
        .listSectionSeparator(.hidden)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if tracks.isEmpty, playableContent.content.type != .track {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Text(playableContent.title)
                        .fontDesign(.rounded)
                        .bold()
                }
            }
        }
        .task {
            artworkURL = playableContent.artwork
            switch (playableContent.content.type, playableContent.content.service) {
            case (.album, .apple):
                guard let album: Album = try? await MusicSearchService().lookup(id: playableContent.content.id) else { return }
                artworkURL = album.artwork?.url(width: 800, height: 800)
                guard let tracks = album.tracks else { return }
                self.tracks = tracks.map(\.toPlayable)
            case (.album, .spotify):
                guard let albumDetails = await MusicSearchService().spotifyAlbumTracksLookup(id: playableContent.content.id) else { return }
                self.tracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
            case (.playlist, .apple):
                guard let playlist: Playlist = try? await MusicSearchService().lookup(id: playableContent.content.id) else { return }
                artworkURL = playlist.artwork?.url(width: 800, height: 800)
                guard let tracks = playlist.tracks else { return }
                self.tracks = tracks.map(\.toPlayable)
            case (.playlist, .spotify):
                guard let playlist: SpotifyPlaylistItems = await MusicSearchService().spotifyPlaylistLookup(id: playableContent.content.id) else { return }
                guard let items = playlist.tracks.items else { return }
                self.tracks = items.map { $0.track.toPlayable(artwork: $0.track.album?.images.thumbnail)}
            case (.track, .apple):
                guard let song: Song = try? await MusicSearchService().lookup(id: playableContent.content.id), let albumID = song.albums?.first?.id.description else { return }
                guard let album: Album = try? await MusicSearchService().lookup(id: albumID) else { return }
                artworkURL = album.artwork?.url(width: 800, height: 800)
                playableContent = album.toPlayable
                guard let tracks = album.tracks else { return }
                self.tracks = tracks.map(\.toPlayable)
            case (.track, .spotify):
                guard let song = await MusicSearchService().spotifyTrackLookup(id: playableContent.content.id) else { return }
                guard let albumDetails = await MusicSearchService().spotifyAlbumTracksLookup(id: song.album.id) else { return }
                playableContent = albumDetails.toPlayable
                artworkURL = albumDetails.images.biggestImageURL
                self.tracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
            case (.album, .library):
                artworkURL = playableContent.artwork
                self.tracks = await sonosService.libraryLookup(ID: playableContent.id)
            case (.playlist, .library):
                artworkURL = playableContent.artwork
                self.tracks = await sonosService.libraryLookup(ID: playableContent.id)
            case (.track, .library):
                artworkURL = playableContent.artwork
                guard let albumName = playableContent.metadata?.album,
                      let albumNameEncoded = albumName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

                self.tracks = await sonosService.libraryAlbum(name: albumName)
                guard let albumPlayable =  await sonosService.libraryLookup(ID: "A:ALBUM:\(albumNameEncoded)").first else { return }
                playableContent = albumPlayable
            case (.album, .tidal):
                // TODO: Add rests of them
                self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: playableContent.content.id)
            default:
                break
            }
        }
    }

    private func play(content: PlayableContent, position: QueuePosition = .now) {
        Task {
            guard let group = group else {
                router.navigate(to: .groupDestination(content: content, position: position))
                return
            }
            
            playHistory.remove(content)
            playHistory.insert(content, at: 0)

            router.dismiss = true
            await sonosService.queue(content: content.content, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
    }

    private func menu(content: PlayableContent) -> some View {
        VStack {
            Button {
                play(content: content, position: .next)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                play(content: content, position: .end)
            } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
    }
}

//#Preview {
//    // https://music.apple.com/us/playlist/dua-lipa-essentials/pl.ee7b1aea4b5f42d398e6cd3084f7396b
//    // https://music.apple.com/us/album/future-nostalgia-the-moonlight-edition/1551178998
//    MediaDetailView(id: "1552269067", title: "Future Nostaliga", kind: .album)
//        .environment(SonosService.shared)
//        .environment(Router())
//}
