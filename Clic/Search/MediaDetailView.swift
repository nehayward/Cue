import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS
import Glur

struct MediaDetailView: View {
    @Environment(Router.self) private var router
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(AlertService.self) private var alertService
    @Environment(MusicSearchService.self) private var musicSearchService: MusicSearchService
    @Environment(MiniPlayerManger.self) private var miniPlayerManager
    @Environment(\.undoManager) private var undoManager
  
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false

    let playableContent: PlayableContent
    @State private var content: PlayableContent?
    @State private var editMode: EditMode = .inactive
    /// Owns the track list so playlist edits can participate in native Undo/Redo.
    @State private var editor = PlaylistEditCoordinator()
    @State private var isLoaded: Bool = false
    @State private var isLoadingMore: Bool = true
    @State private var isFetchingPage: Bool = false
    /// Raw number of source items consumed so far. This is the real pagination offset for
    /// offset-based services and can exceed `tracks.count` when a page contains items that
    /// drop out (e.g. Spotify playlists with removed/local tracks that decode to nil).
    @State private var loadedItemCount: Int = 0
    @State private var totalSongs: Int?

    /// Number of rows before the end at which we start prefetching the next page.
    /// Loading ahead of the visible edge hides network latency so scrolling stays smooth.
    private static let prefetchThreshold = 10
    @State private var duration: Duration?
    @State private var selection: Set<Int> = []
    @State private var nextCursor: String?
    @State private var showNavigationTitle: Bool = false

    /// Proxies the view's existing `tracks` usage onto the coordinator (the source of truth),
    /// so native undo/redo mutations are reflected in the UI.
    private var tracks: [PlayableContent] {
        get { editor.tracks }
        nonmutating set { editor.tracks = newValue }
    }

    var maxHeight: Double {
        UIDevice.current.userInterfaceIdiom == .phone ? 340 : 400
    }

    /// For a non-Sonos service playlist, whether the user can actually edit it (owns it or it's
    /// collaborative). Confirmed at load — streaming services let you browse playlists you can't edit.
    @State private var serviceEditable = false

    /// Playlists whose tracks can be removed in-place. Streaming playlists also require confirmed
    /// ownership, so editing isn't offered on followed/editorial playlists.
    private var isEditablePlaylist: Bool {
        playableContent.isSonosPlaylist || (playableContent.isEditableServicePlaylist && serviceEditable)
    }

    /// Playlists whose tracks can be reordered. Excludes Apple Music (no reorder API) and Deezer
    /// (its reorder takes a full track-id list, unsafe for a paginated/partially loaded playlist),
    /// and requires confirmed ownership for streaming playlists.
    private var canReorderTracks: Bool {
        playableContent.isSonosPlaylist
            || ((playableContent.isSpotifyPlaylist || playableContent.isPlexPlaylist) && serviceEditable)
    }
    
    var body: some View {
        @Bindable var router = router
        List(selection: $selection) {
            artworkSection
            ForEach(Array(tracks.enumerated()), id: \.element.trackID) { index, item in
                VStack {
                    PlayableContentView(item: item,
                                        parent: content ?? playableContent,
                                        hideArtwork: content?.content.type == .album,
                                        hideContentType: true,
                                        index: index + 1,
                                        dismissOnComplete: true,
                                        total: totalSongs ?? tracks.count,
                                        onRemoveFromPlaylist: isEditablePlaylist ? { removeTrack(at: index) } : nil)
                }
                .tag(index)
                .swipeActions(edge: .trailing) {
                    if isEditablePlaylist {
                        Button(role: .destructive) {
                            removeTrack(at: index)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .opacity(item.isPlayable ? 1 : 0.6)
                .disabled(!item.isPlayable)
                .task {
                    guard playableContent.content.type.isPlaylist else {
                        return
                    }

                    if playableContent.content.type == .playlist && playableContent.content.service == .apple {
                        return
                    }

                    let hasMore = totalSongs.map { loadedItemCount < $0 } ?? true
                    let nearEnd = index >= tracks.count - Self.prefetchThreshold
                    if nearEnd && isLoadingMore && hasMore {
                        await updateTracks(offset: loadedItemCount)
                    }
                }
                .listRowBackground(Color.white.opacity(0.001))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .onMove(perform: canReorderTracks ? move : nil)
            if tracks.isEmpty {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.white.opacity(0.001))
                } else {
                    ContentUnavailableView(
                        "No Tracks",
                        systemImage: "music.note",
                        description: Text("This album or playlist has no tracks.")
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.white.opacity(0.001))
                }
            }
        }
        .environment(\.editMode, $editMode)
        .onChange(of: editMode.isEditing) { _, editing in
            withAnimation(.spring) { miniPlayerManager.hidden = editing }
        }
        .onDisappear {
            miniPlayerManager.hidden = false
            AudioPlaybackService.shared.stopPreview()
        }
        .ignoresSafeArea(edges: .top)
        .onScrollOffset(exceeds: 300, set: $showNavigationTitle)
        .scrollEdgeEffectHidden26(!showNavigationTitle)
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            if isEditablePlaylist && !selection.isEmpty {
                Button(role: .destructive) {
                    if playableContent.isEditableServicePlaylist {
                        editor.removeSelected(Array(selection), undoManager: undoManager)
                        selection.removeAll()
                    } else {
                        Task {
                            // Descending so each local removal keeps the remaining indices valid.
                            for index in Array(selection).sorted(by: >) where tracks.indices.contains(index) {
                                let removed = (try? await SonosService.shared.removeTrackFromPlaylist(
                                    playlistID: playableContent.id,
                                    index: index
                                )) != nil
                                if removed { tracks.remove(at: index) }
                            }
                            selection.removeAll()
                        }
                    }
                } label: {
                    Text("Remove (\(selection.count))")
                        .frame(maxWidth: .infinity)
                        .monospacedDigit()
                        .bold()
                        .geometryGroup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
#if targetEnvironment(macCatalyst)
                .padding(.bottom)
#endif
            }
        }
        .task {
            editor.configure(playlist: playableContent)
            // Confirm edit permission concurrently so it doesn't delay track loading.
            async let editable = confirmServiceEditable()
            await updateTracks(offset: loadedItemCount)
            serviceEditable = await editable
        }
        .background {
            // Hidden ⌘Z / ⌘⇧Z bindings to drive the playlist editor's UndoManager.
            // opacity(0) keeps the shortcuts active while making the buttons invisible.
            if isEditablePlaylist {
                Group {
                    Button("Undo") { undoManager?.undo() }
                        .keyboardShortcut("z", modifiers: .command)
                    Button("Redo") { undoManager?.redo() }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle(content?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(content?.title ?? "")
                        .fontDesign(.rounded)
                        .bold()
                        .multilineTextAlignment(.center)
                    Text(content?.metadata?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)
                        .bold()
                        .multilineTextAlignment(.center)
                }
                .opacity(showNavigationTitle ? 1 : 0)
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditablePlaylist {
                    Button {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Label(editMode.isEditing ? "Done" : "Edit",
                              systemImage: editMode.isEditing ? "checkmark" : "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut("e", modifiers: [])
                }
            }
        }
        .animation(.smooth, value: showNavigationTitle)
    }
    
    @ViewBuilder
    private var artworkSection: some View {
        Color.clear.overlay {
            ZStack {
                LazyImage(url: content?.artwork) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .blur(radius: 100)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: maxHeight)
                LazyImage(url: content?.artwork) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .glur(radius: 30, // The total radius of the blur effect when fully applied.
                                  offset: 0.6, // The distance from the view's edge to where the effect begins, relative to the view's size.
                                  interpolation: 0.4, // The distance from the offset to where the effect is fully applied, relative to the view's size.
                                  direction: .down, // The direction in which the effect is applied.
                                  noise: 0.1, // The amount of noise that should be applied to the view.
                                  drawingGroup: false // Whether or not to pre-render the modified view with `drawingGroup()`.
                            )
                            .frame(maxWidth: 400, maxHeight: maxHeight)
                            .clipped()
                    }
                }
            }
        }
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0.0),
                    .init(color: .clear, location: 0.55)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .stretchy()
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading) {
                headerOverlay
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .frame(height: maxHeight)
        .listRowBackground(Color.white.opacity(0.001))
        .listSectionSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }
    
    @ViewBuilder
    private var headerOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content?.title ?? "")
                .font(.title)
                .foregroundStyle(.white)
                .fontWeight(.black)
                .fontDesign(.rounded)
                .minimumScaleFactor(0.3)
                .allowsTightening(true)
                .lineLimit(1)
            HStack(spacing: 0) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.navigate(to: .artistDetail(content: content ?? playableContent, group: selectedGroupService.group))
                } label: {
                    Text(content?.metadata?.artist ?? "")
                        .bold()
                        .lineLimit(1)
                        .underline()
                }
                .buttonStyle(.plain)
                
                let yearText = content?.metadata?.albumYear?.formatted(.dateTime.year())
                let songsCount = totalSongs ?? (tracks.isEmpty ? nil : tracks.count)
                let songsText = songsCount.map { "\($0) Songs" }

                let durationText: String? = {
                    if let duration {
                        return duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
                    }
                    if totalDuration.components.seconds > 0 {
                        return totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
                    }
                    return nil
                }()
                let metadata = [yearText, songsText, durationText].compactMap { $0 }.joined(separator: " • ")
                let metadataText = metadata.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\(metadata)"
                Text("\(content?.metadata?.artist == nil ? "" : " • ")")
                Text(metadataText)
            }
            .font(.caption)
            .padding(.bottom, 4)
            HStack(spacing: 12) {
                Button {
                    play()
                } label: {
                    Text("\(Image(systemName: "play.fill")) Play")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .glassButton()
                .foregroundStyle(.primary)
                
                Button {
                    play([.normal, .shuffle])
                } label: {
                    Text("\(Image(systemName: "shuffle")) Shuffle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .glassButton()
                .foregroundStyle(.primary)
                
                if let content {
                    Menu {
                        PlayableMenuView(item: content)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 24)
                    }
                    .buttonBorderShape(.circle)
                    .contentShape(.rect)
                    .glassButton()
                }
            }
            .bold()
            .fontDesign(.rounded)
        }
        .fontDesign(.rounded)
        .foregroundStyle(.white)
    }
    
    private func play(_ playMode: PlayMode = .normal) {
        Task { @MainActor in
            let currentContent = content ?? playableContent
            let defaultPosition = QueuePosition.defaultPosition(
                for: currentContent.content.type,
                replaceQueueByDefault: replaceQueueByDefault
            )
            let queue: ((GroupRoom, QueuePosition) async throws -> Void) = { [currentContent, totalSongs, tracks] group, selectedPosition in
                await SonosService.shared.setPlayMode(group.ip, mode: playMode)
                group.playMode = playMode

                QueueManager.shared.addToQueue(
                    item: QueueItem(
                        playableContent: currentContent,
                        group: group,
                        position: selectedPosition,
                        total: totalSongs ?? tracks.count,
                        showBanner: false
                    )
                )
                Router.main.show(destination: .player(groupID: group.coordinatorID))
                return
            }

            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onQueueSelection: queue, defaultPosition: defaultPosition, content: currentContent))
                return
            }

            try await queue(group, defaultPosition)
        }
    }
    
    private var totalDuration: Duration {
        Duration.seconds(tracks.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
    }
    
    private func updateTracks(offset: Int = 0) async {
        // Avoid firing duplicate concurrent requests for the same page. With prefetching,
        // several near-the-end rows can trigger a load before the first one returns; this
        // guard collapses them into a single in-flight fetch.
        guard !isFetchingPage else { return }
        isFetchingPage = true

        // Ensure isLoaded is set even if we return early
        defer {
            isFetchingPage = false
            if offset == 0 {
                isLoaded = true
            }
        }

        // If already an album or playlist type, set immediately (no spinner needed)
        if [.album, .libraryAlbum].contains(playableContent.content.type) || playableContent.content.type.isPlaylist {
            content = playableContent
        }

        if offset > 0, !playableContent.content.type.isPlaylist {
            return
        }

        var newTracks: [PlayableContent] = []
        // How many raw source items this page consumed. Defaults to the number of playable
        // tracks produced, but services that can drop items mid-page (Spotify) override it
        // with the true page size so the next offset doesn't re-read the dropped rows.
        var consumedCount: Int?
        switch (playableContent.content.type, playableContent.content.service) {
        case (.album, .apple):
            guard let album: Album = try? await musicSearchService.lookup(id: playableContent.content.id) else { return }
            content = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = await musicSearchService.tracksToPlayableWithPreviews(tracks)
        case (.libraryAlbum, .apple):
            if let album = await musicSearchService.appleLibraryAlbum(id: playableContent.id), let playableAlbum = album.data.first?.toPlayable {
                content = playableAlbum
            }
            newTracks = await AppleMusicBrowseService.shared.albumLookup(id: content?.id ?? playableContent.id)
        case (.album, .spotify):
            guard let albumDetails = await musicSearchService.spotifyAlbumTracksLookup(id: playableContent.content.id) else { return }
            let albumPlayable = albumDetails.toPlayable
            content = albumPlayable
            newTracks = albumDetails.tracks.items.compactMap { $0.toPlayable(album: albumPlayable, thumbnail: albumDetails.images.thumbnail, artwork: albumDetails.images.thumbnail) }
        case (.playlist, .apple):
            guard let playlist = try? await musicSearchService.getTracksFromPlaylist(id: playableContent.content.id) else { return }
            newTracks = await musicSearchService.tracksToPlayableWithPreviews(playlist)
        case (.libraryPlaylist, .apple):
            let (tracks, playlistCount) = await AppleMusicBrowseService.shared.tracksForUserPlaylists(id: playableContent.id, offset: offset)
            newTracks = tracks
            totalSongs = playlistCount
        case (.playlist, .spotify):
            guard let playlist = await musicSearchService.spotifyPlaylistTracks(id: playableContent.content.id, offset: offset) else { return }
            totalSongs = playlist.total
            // Advance by the raw page size, not the playable count: a page can contain items
            // (removed/local tracks) that decode to nil, and offset is a raw playlist index.
            consumedCount = playlist.items.count
            newTracks = playlist.items
                .compactMap {
                    $0.track?.toPlayable(
                        album: nil,
                        thumbnail: $0.track?.album?.images?.thumbnail,
                        artwork: $0.track?.album?.images?.thumbnail,
                        fingerprint: $0.uid
                    )
                }
            // Stop once we've consumed the whole playlist; dropped items mean tracks.count
            // alone never reaches total, which would otherwise keep refetching empty tails.
            if playlist.items.isEmpty || offset + playlist.items.count >= playlist.total {
                isLoadingMore = false
            }
        case (.track, .apple):
            guard let song: Song = try? await musicSearchService.lookup(id: playableContent.content.id), let albumID = song.albums?.first?.id.description else { return }
            guard let album: Album = try? await musicSearchService.lookup(id: albumID) else { return }
            content = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = await musicSearchService.tracksToPlayableWithPreviews(tracks)
        case (.libraryTrack, .apple):
            guard let catalogSong = await musicSearchService.appleLibraryLookup(id: playableContent.content.id), let id = catalogSong.data.first?.id else { return }
            guard let song: Song = try? await musicSearchService.lookup(id: id), let albumID = song.albums?.first?.id.description else { return }
            guard let album: Album = try? await musicSearchService.lookup(id: albumID) else { return }
            content = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = await musicSearchService.tracksToPlayableWithPreviews(tracks)
        case (.track, .spotify):
            guard let song = await musicSearchService.spotifyTrackLookup(id: playableContent.content.id) else { return }
            guard let albumID = song.album.id else { return }
            guard let albumDetails = await musicSearchService.spotifyAlbumTracksLookup(id: albumID) else { return }
            let albumPlayable = albumDetails.toPlayable
            content = albumPlayable
            newTracks = albumDetails.tracks.items.compactMap { $0.toPlayable(album: albumPlayable, thumbnail: albumDetails.images.thumbnail, artwork: albumDetails.images.thumbnail) }
        case (.album, .library):
            newTracks = await SonosService.shared.libraryLookup(ID: playableContent.id)
        case (.playlist, .library):
            newTracks = await SonosService.shared.sonosPlaylistsTracks(for: playableContent.id, offset: tracks.count, limit: 100)
        case (.libraryImportedPlaylists, .library):
            let id = playableContent.id.replacingOccurrences(of: "x-file-cifs", with: "S")
            newTracks = await SonosService.shared.libraryLookup(ID: id)
        case (.track, .library):
            guard let albumName = playableContent.metadata?.album,
                  let albumNameEncoded = albumName.addingPercentEncoding(withAllowedCharacters: .sonosQueryAllowed) else { return }
            
            newTracks = await SonosService.shared.libraryAlbum(name: albumName)
            guard let albumPlayable =  await SonosService.shared.libraryLookup(ID: "A:ALBUM:\(albumNameEncoded)").first else { return }
            content = albumPlayable
        case (.album, .tidal):
            newTracks = await musicSearchService.lookupTidalAlbumTracks(id: playableContent.content.id)
        case (.track, .tidal):
            if let albumID = playableContent.metadata?.albumID {
                guard let album = await musicSearchService.lookupTidalAlbum(with: albumID) else { return }
                newTracks = await musicSearchService.lookupTidalAlbumTracks(id: albumID)
                content = album
            } else {
                guard let albumID = await musicSearchService.lookupTidalTrack(with: playableContent.id)?.metadata?.albumID else { return }
                guard let album = await musicSearchService.lookupTidalAlbum(with: albumID) else { return }
                newTracks = await musicSearchService.lookupTidalAlbumTracks(id: albumID)
                content = album
            }
        case (.playlist, .tidal):
            (newTracks, nextCursor) = await musicSearchService.lookupTidalPlaylist(id: playableContent.content.id, cursor: nextCursor)
            if nextCursor == nil {
                isLoadingMore = false
            }
            // MARK: Plex
        case (.track, .plex):
            if let albumID = playableContent.metadata?.albumID {
                guard let album = await musicSearchService.lookupPlexAlbum(id: albumID) else { return }
                content = album
                newTracks = await musicSearchService.lookupPlexAlbumSongs(id: albumID)
            } else {
                guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                      let albumID = await musicSearchService.lookupPlexSong(with: id)?.metadata?.albumID,
                      let album = await musicSearchService.lookupPlexAlbum(id: albumID) else { return }
                content = album
                newTracks = await musicSearchService.lookupPlexAlbumSongs(id: albumID)
            }
        case (.album, .plex):
            newTracks = await musicSearchService.lookupPlexAlbumSongs(id: playableContent.content.id)
        case (.playlist, .plex):
            (totalSongs, newTracks, duration) = await musicSearchService.lookupPlexPlaylists(id: playableContent.content.id, offset: offset)
        case (.playlist, .soundcloud):
            (newTracks, nextCursor) = await musicSearchService.lookupSoundCloudPlaylistTracks(with: playableContent.content.id, nextCursor: nextCursor)
            if nextCursor == nil {
                isLoadingMore = false
            }
        case (.album, .deezer):
            newTracks = await musicSearchService.lookupDeezerAlbumTracks(id: playableContent.content.id)
            isLoadingMore = false
        case (.playlist, .deezer):
            newTracks = await musicSearchService.lookupDeezerPlaylistTracks(id: playableContent.content.id)
            isLoadingMore = false
        case (.track, .deezer):
            let albumID: String?
            if let existing = playableContent.metadata?.albumID {
                albumID = existing
            } else {
                albumID = await musicSearchService.lookupDeezerTrack(with: playableContent.content.id)?.metadata?.albumID
            }
            guard let albumID else { return }
            guard let album = await musicSearchService.lookupDeezerAlbum(with: albumID) else { return }
            content = album
            newTracks = await musicSearchService.lookupDeezerAlbumTracks(id: albumID)
            isLoadingMore = false
        default:
            return
        }
        appendTracksAvoidingDuplicates(newTracks: newTracks, to: &tracks)
        loadedItemCount += consumedCount ?? newTracks.count

        if let content {
            RecentSearchesStorage.shared.addOrMoveToFront(byID: content)
        }
    }
    
    func appendTracksAvoidingDuplicates(newTracks: [PlayableContent], to tracks: inout [PlayableContent]) {
        // Seed counts from the already-loaded tracks in a single pass, then update as we
        // append. Avoids re-scanning the whole (growing) tracks array for every new row,
        // which otherwise makes each page append slower the further you paginate.
        var idCounts: [String: Int] = tracks.reduce(into: [:]) { counts, track in
            counts[track.id, default: 0] += 1
        }

        for var newTrack in newTracks {
            let originalID = newTrack.id
            let existingCount = idCounts[originalID, default: 0]

            if existingCount > 0 {
                newTrack.metadata?.position = existingCount + 1
            }

            idCounts[originalID] = existingCount + 1
            tracks.append(newTrack)
        }
    }
    
    /// Removes the track at `index` from the playlist, dispatching to Sonos or the streaming service.
    private func removeTrack(at index: Int) {
        if playableContent.isSonosPlaylist {
            Task {
                try? await SonosService.shared.removeTrackFromPlaylist(playlistID: playableContent.id, index: index)
                tracks.remove(at: index)
            }
        } else if playableContent.isEditableServicePlaylist && serviceEditable {
            editor.removeTrack(at: index, undoManager: undoManager)
        }
    }

    /// Whether the current streaming playlist is editable by the user (owned/collaborative).
    private func confirmServiceEditable() async -> Bool {
        guard playableContent.isEditableServicePlaylist else { return false }
        return await musicSearchService.canEditServicePlaylist(playableContent)
    }

    private func move(from source: IndexSet, to destination: Int) {
        if playableContent.isSonosPlaylist {
            guard let sourceIndex = source.first else { return }
            let previous = tracks
            tracks.move(fromOffsets: source, toOffset: destination)
            Task {
                do {
                    try await SonosService.shared.reorderPlaylist(playlistID: playableContent.id, from: sourceIndex, to: destination)
                } catch {
                    tracks = previous
                    alertService.showAlert(with: "Couldn’t reorder track", imageName: "exclamationmark.triangle")
                }
            }
        } else {
            editor.moveTrack(from: source, to: destination, playlist: playableContent)
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var show: Bool = true
    Button {
        show.toggle()
    } label: {
        Text("TEST")
    }
    .sheet(isPresented: $show) {
        NavigationStack {
            MediaDetailView(playableContent: .bazAlbum)
                .environment(Router.main)
                .environment(SelectedGroupService())
                .environment(AlertService.shared)
                .environment(MusicSearchService.shared)
                .withEnvironments()
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        MediaDetailView(playableContent: .harry)
            .environment(Router.main)
            .environment(SelectedGroupService())
            .environment(AlertService.shared)
            .environment(MusicSearchService.shared)
            .withEnvironments()
    }
}
#endif

