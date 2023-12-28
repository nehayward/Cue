import CloudStorage
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit
import Kingfisher

struct SpotifySearchView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Binding var spotifyResult: SpotifyResult?
    @Binding var filters: [FilterSelection]

    var group: GroupRoom

    var body: some View {
        if filters.filter(\.isFiltered).isEmpty {
            Group {
                if let playlists = spotifyResult?.playlists?.items {
                    playlist(playlists: playlists)
                }
                if let tracks = spotifyResult?.tracks?.items {
                    trackSection(tracks: tracks)
                }
                // TODO: Add back when you can queue
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
                case .tracks:
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

    private func trackSection(tracks: [SpotifyTrackItems]) -> some View {
        Section {
            ForEach(tracks) { item in
                Button {
                    dismiss()
                    Task {
                        await sonosService.queueSpotifyTrack(id: item.id, group: group)
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: item.album.images.first?.url ?? ""),
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
                            Text(item.name)
                            Text(item.artists.first?.name ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        dismiss()
                        Task {
                            await sonosService.queueSpotifyTrack(id: item.id, group: group, position: .next)
                        }
                    } label: {
                        Label("Play Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                }
            }
        } header: {
            Text("Tracks")
        }
    }

    private func artistRow(artists: [SpotifyArtistsItems]) -> some View {
        Section {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(artists) { item in
                        VStack {
                            AsyncImage( url: URL(string: item.images.first?.url ?? ""),
                                        transaction: Transaction(animation: .snappy)
                            ) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                default:
                                    RoundedRectangle(cornerRadius: 12)
                                        .foregroundStyle(.thinMaterial)
                                        .frame(width: 60, height: 60)
                                }
                            }
                            VStack(alignment: .leading) {
                                Text(item.name)
                            }
                        }
                        .fontDesign(.rounded)
                        .onTapGesture {
                            dismiss()
                            Task {
                                await sonosService.queueSpotifyTrack(id: item.id, group: group)
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("Artist")
        }
    }

    private func albumRow(albums: [SpotifyAlbumItems]) -> some View {
        Section {
            ForEach(albums) { album in
                Button {
                    dismiss()
                    Task {
                        await sonosService.queueSpotifyAlbum(id: album.id, group: group, position: .now)
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: album.images.first?.url ?? ""),
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
                            Text(album.name)
                            Text(album.artists.first?.name ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fontDesign(.rounded)
                }
            }
        } header: {
            Text("Albums")
        }
    }

    private func playlist(playlists: [SpotifyPlaylistItems]) -> some View {
        Section {
            ForEach(playlists) { item in
                Button {
                    dismiss()
                    Task {
                        await sonosService.queueSpotifyPlaylist(
                            id: item.id,
                            title: item.name,
                            owner: item.owner.displayName,
                            on: group.coordinatorRoom.ip,
                            group: group
                        )
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: item.images.first?.url ?? ""),
                                   transaction: Transaction(animation: .snappy)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipped()
                            default:
                                RoundedRectangle(cornerRadius: 12)
                                    .foregroundStyle(.thinMaterial)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.owner.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Playlist")
        }
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

