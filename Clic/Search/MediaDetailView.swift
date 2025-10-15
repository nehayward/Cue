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
    @Environment(Router.self) private var router
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(AlertService.self) private var alertService
    @Environment(MusicSearchService.self) private var musicSearchService: MusicSearchService

    @State var playableContent: PlayableContent
    @State private var editMode: EditMode = .inactive
    @State private var tracks: [PlayableContent] = []
    @State private var isLoaded: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var totalSongs: Int?
    @State private var duration: Duration?
    @State private var selection: Set<Int> = []

    var body: some View {
        @Bindable var router = router
        List(selection: $selection) {
            VStack(spacing: 0) {
                LazyImage(url: playableContent.artwork) { state in
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
                    } else {
                        Rectangle()
                            .foregroundStyle(.ultraThickMaterial)
                            .aspectRatio(contentMode: .fit)
                            .overlay {
                                if state.error != nil {
                                    Image(systemName: "music.note")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, height: 100)
                                }
                            }
                    }
                }
                .transition(.opacity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .scaledToFit()
                .overlay(alignment: .bottomTrailing) {
                    playableContent.content.service.icon
                        .frame(width: 24, height: 24, alignment: .trailing)
                        .padding([.bottom, .trailing])
                }
                // TODO: Add back for plex, need to handle image size changes
//                ContentArtworkView(content: playableContent)
//                    .frame(idealWidth: 320, idealHeight: 320)
            }
            .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            VStack(spacing: 0) {
                Text(playableContent.subtitle)
                // MARK: Add back
//                if let artist = playableContent.metadata?.artist {
//                    ZStack {
//                        NavigationLink(value: RouterDestination.artistDetail(content: playableContent, group: selectedGroupService.group)) {
//                            EmptyView()
//                        }
//                        .opacity(0)
//                        Button {
//                            router.navigate(to: RouterDestination.artistDetail(content: playableContent, group: selectedGroupService.group))
//                        } label: {
//                            Text(artist)
//                                .multilineTextAlignment(.center)
//                                .fontDesign(.rounded)
//                                .font(.title3)
//                                .frame(maxWidth: .infinity)
//                                .lineLimit(1, reservesSpace: true)
//                                .foregroundStyle(.accent)
//                        }
//                    }
//                }
//
                HStack(spacing: 0) {
                    if let totalSongs {
                        Text(totalSongs, format: .number)
                    } else {
                        Text("\(tracks.count.formatted())")
                    }
                    Text(" Songs")
                    if let duration {
                        Text(" • \(duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                    } else {
                        if totalDuration.components.seconds > 0  {
                            Text(" • \(totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                        }
                    }
                }
//                if let audioFormat = playableContent.metadata?.audioCodec {
//                    Text(audioFormat)
//                }
            }
            .frame(maxWidth: .infinity)
            .fontDesign(.rounded)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            HStack {
                Button {
                    play()
                } label: {
                    Text("Play")
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.foreground)
                }
                .bold()
                .buttonStyle(.bordered)
                .tint(.accent)

                Button {
                    play([.shuffle, .normal])
                } label: {
                    Text("Shuffle")
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.foreground)
                }
                .bold()
                .buttonStyle(.bordered)
                .tint(.accent)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            ForEach(Array(tracks.enumerated()), id: \.element.trackID) { index, item in
                VStack {
                    PlayableContentView(item: item,
                                        parent: playableContent,
                                        hideArtwork: playableContent.content.type == .album,
                                        hideContentType: true,
                                        index: index + 1,
                                        dismissOnComplete: true,
                                        total: totalSongs ?? tracks.count)
                }
                .tag(index)
                .swipeActions(edge: .trailing) {
                    if playableContent.isSonosPlaylist {
                        Button(role: .destructive) {
                            Task {
                                try await SonosService.shared.removeTrackFromPlaylist(playlistID: playableContent.id, index: index)
                                tracks.remove(at: index)
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .disabled(!(item.metadata?.isPlayable ?? true))
                .task {
                    guard playableContent.content.type.isPlaylist else {
                        return
                    }
                    
                    if playableContent.content.type == .playlist && playableContent.content.service == .apple {
                        return
                    }
                    
                    if index >= tracks.count - 1 && !isLoadingMore && (totalSongs == nil || tracks.count < totalSongs!) {
                        Task {
                            await updateTracks(offset: tracks.count)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .onMove(perform: playableContent.isSonosPlaylist ? move : nil)

            if tracks.isEmpty, !isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listRowSpacing(2)
        .contentMargins(.horizontal, EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20), for: .scrollContent)
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) {
            if playableContent.isSonosPlaylist {
                Button(role: .destructive) {
                    Task {
                        // Remove tracks using their actual queue positions
                        for index in Array(selection).sorted(by: >) {
                            try await SonosService.shared.removeTrackFromPlaylist(
                                playlistID: playableContent.id,
                                index: index
                            )
                            tracks.remove(at: index)
                        }
                        
                        // Clear selection
                        selection.removeAll()
                    }
                } label: {
                    Text("Delete Selected (\(selection.count))")
                        .frame(maxWidth: .infinity)
                        .monospacedDigit()
                        .bold()
                        .geometryGroup()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .offset(y: !selection.isEmpty ? 0 : 200)
                .animation(.interactiveSpring, value: selection.isEmpty)
#if targetEnvironment(macCatalyst)
                .padding(.bottom)
#endif
            }
        }
        .task {
            await updateTracks(offset: tracks.count)
        }
        .listStyle(.sidebar)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationBarTitleDisplayMode(.inline)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(playableContent.title)
                    .fontDesign(.rounded)
                    .bold()
                    .multilineTextAlignment(.center)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if playableContent.isSonosPlaylist {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                }
                Menu {
                    PlayableMenuView(item: playableContent)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(maxWidth: 40, maxHeight: .infinity)
                        .background(.clear)
                        .bold()
                        .foregroundStyle(.foreground)
                        .contentShape(.rect)
                }
                .contentShape(.rect)
            }
        }
    }

    private func play(_ playMode: PlayMode = .normal) {
        Task { @MainActor in
            let queue: ((GroupRoom) async throws -> Void) = { group in
                QueueManager.shared.addToQueue(
                        item: QueueItem(
                            playableContent: playableContent,
                            group: group,
                            position: [.playlist, .libraryPlaylist].contains(playableContent.content.type) ? .replace : .now,
                            total: totalSongs ?? tracks.count,
                            playMode: playMode,
                            showBanner: false
                        )
                    )
                    Router.main.show(destination: .player(groupID: group.coordinatorID))
                return
            }
            
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queue, content: playableContent))
                return
            }
        
            try await queue(group)
        }
    }

    private var totalDuration: Duration {
        Duration.seconds(tracks.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
    }

    private func updateTracks(offset: Int = 0) async {
        if offset > 0, !playableContent.content.type.isPlaylist {
            return
        }
        
        var newTracks: [PlayableContent] = []
        switch (playableContent.content.type, playableContent.content.service) {
        case (.album, .apple):
            guard let album: Album = try? await musicSearchService.lookup(id: playableContent.content.id) else { return }
            playableContent = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.libraryAlbum, .apple):
            if let album = await musicSearchService.appleLibraryAlbum(id: playableContent.id), let playableAlbum = album.data.first?.toPlayable {
                playableContent = playableAlbum
            }
            newTracks = await AppleMusicBrowseService.shared.albumLookup(id: playableContent.id)
        case (.album, .spotify):
            guard let albumDetails = await musicSearchService.spotifyAlbumTracksLookup(id: playableContent.content.id) else { return }
            playableContent = albumDetails.toPlayable
            newTracks = albumDetails.tracks.items.compactMap { $0.toPlayable(album: playableContent, thumbnail: albumDetails.images.thumbnail, artwork: albumDetails.images.thumbnail) }
        case (.playlist, .apple):
            guard let playlist = try? await musicSearchService.getTracksFromPlaylist(id: playableContent.content.id) else { return }
            newTracks = playlist.map(\.toPlayable)
        case (.libraryPlaylist, .apple):
            let (tracks, playlistCount) = await AppleMusicBrowseService.shared.tracksForUserPlaylists(id: playableContent.id, offset: offset)
            newTracks = tracks
            totalSongs = playlistCount
        case (.playlist, .spotify):
            guard let playlist = await musicSearchService.spotifyPlaylistTracks(id: playableContent.content.id, offset: offset) else { return }
            totalSongs = playlist.total
            newTracks = playlist.items
                .compactMap {
                    $0.track.toPlayable(
                        album: nil,
                        thumbnail: $0.track.album?.images?.thumbnail,
                        artwork: $0.track.album?.images?.thumbnail,
                        fingerprint: $0.uid
                    )
                }
        case (.track, .apple):
            guard let song: Song = try? await musicSearchService.lookup(id: playableContent.content.id), let albumID = song.albums?.first?.id.description else { return }
            guard let album: Album = try? await musicSearchService.lookup(id: albumID) else { return }
            playableContent = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.libraryTrack, .apple):
            guard let catalogSong = await musicSearchService.appleLibraryLookup(id: playableContent.content.id), let id = catalogSong.data.first?.id else { return }
            guard let song: Song = try? await musicSearchService.lookup(id: id), let albumID = song.albums?.first?.id.description else { return }
            guard let album: Album = try? await musicSearchService.lookup(id: albumID) else { return }
            playableContent = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.track, .spotify):
            guard let song = await musicSearchService.spotifyTrackLookup(id: playableContent.content.id) else { return }
            guard let albumID = song.album.id else { return }
            guard let albumDetails = await musicSearchService.spotifyAlbumTracksLookup(id: albumID) else { return }
            playableContent = albumDetails.toPlayable
            newTracks = albumDetails.tracks.items.compactMap { $0.toPlayable(album: playableContent, thumbnail: albumDetails.images.thumbnail, artwork: albumDetails.images.thumbnail) }
        case (.album, .library):
            newTracks = await SonosService.shared.libraryLookup(ID: playableContent.id)
        case (.playlist, .library):
            newTracks = await SonosService.shared.sonosPlaylistsTracks(for: playableContent.id, offset: tracks.count, limit: 100)
        case (.libraryImportedPlaylists, .library):
            let id = playableContent.id.replacingOccurrences(of: "x-file-cifs", with: "S")
            newTracks = await SonosService.shared.libraryLookup(ID: id)
        case (.track, .library):
            guard let albumName = playableContent.metadata?.album,
                  let albumNameEncoded = albumName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

            newTracks = await SonosService.shared.libraryAlbum(name: albumName)
            guard let albumPlayable =  await SonosService.shared.libraryLookup(ID: "A:ALBUM:\(albumNameEncoded)").first else { return }
            playableContent = albumPlayable
        case (.album, .tidal):
            newTracks = await musicSearchService.lookupTidalAlbumTracks(id: playableContent.content.id)
        case (.track, .tidal):
            if let albumID = playableContent.metadata?.albumID {
                guard let album = await musicSearchService.lookupTidalAlbum(with: albumID) else { return }
                newTracks = await musicSearchService.lookupTidalAlbumTracks(id: albumID)
                playableContent = album
            } else {
                guard let albumID = await musicSearchService.lookupTidalTrack(with: playableContent.id)?.metadata?.albumID else { return }
                guard let album = await musicSearchService.lookupTidalAlbum(with: albumID) else { return }
                newTracks = await musicSearchService.lookupTidalAlbumTracks(id: albumID)
                playableContent = album
            }
        case (.playlist, .tidal):
//            newTracks = await musicSearchService.lookupTidalPlaylist(id: playableContent.content.id)
            break
        // MARK: Plex
        case (.track, .plex):
            if let albumID = playableContent.metadata?.albumID {
                guard let album = await musicSearchService.lookupPlexAlbum(id: albumID) else { return }
                playableContent = album
                newTracks = await musicSearchService.lookupPlexAlbumSongs(id: albumID)
            } else {
                guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                      let albumID = await musicSearchService.lookupPlexSong(with: id)?.metadata?.albumID,
                      let album = await musicSearchService.lookupPlexAlbum(id: albumID) else { return }
                playableContent = album
                newTracks = await musicSearchService.lookupPlexAlbumSongs(id: albumID)
            }
        case (.album, .plex):
            newTracks = await musicSearchService.lookupPlexAlbumSongs(id: playableContent.content.id)
        case (.playlist, .plex):
            (totalSongs, newTracks, duration) = await musicSearchService.lookupPlexPlaylists(id: playableContent.content.id, offset: offset)
        case (.playlist, .soundcloud):
            newTracks = await musicSearchService.lookupSoundCloudPlaylistTracks(with: playableContent.content.id, nextCursor: nil)
        default:
            assertionFailure("Implement this.")
        }
        appendTracksAvoidingDuplicates(newTracks: newTracks, to: &tracks)
        isLoaded = true
        isLoadingMore = false
    }
    
    func appendTracksAvoidingDuplicates(newTracks: [PlayableContent], to tracks: inout [PlayableContent]) {
        var idCounts: [String: Int] = [:]

        for var newTrack in newTracks {
            let originalID = newTrack.id
            let existingCount = idCounts[originalID] ?? tracks.filter { $0.id == originalID }.count

            if existingCount > 0 {
                newTrack.metadata?.position = existingCount + 1
            }

            idCounts[originalID] = existingCount + 1
            tracks.append(newTrack)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        Task {
            guard let sourceIndex = source.first else { return }
            try await SonosService.shared.reorderPlaylist(playlistID: playableContent.id, from: sourceIndex, to: destination)
        }
    }
}
