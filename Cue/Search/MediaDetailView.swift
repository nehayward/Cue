import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import Nuke
import NukeUI
import VibesDS

struct MediaDetailView: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesPadLayout) private var usesPadLayout
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(AlertService.self) private var alertService
    @Environment(MusicSearchService.self) private var musicSearchService: MusicSearchService
    @Environment(MiniPlayerManger.self) private var miniPlayerManager

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
    /// The order the songs are listed in. A playlist offers others
    /// (`sortsSongs`); the choice is remembered per playlist.
    @State private var songSort: PlaylistSongSort = .playlistOrder
    @State private var songSortReversed = false
    /// The indices of `tracks` in `songSort`'s order, once every song is in
    /// to sort; nil while the songs are in the playlist's own order.
    @State private var sortedOrder: [Int]?
    /// The rest of the playlist is loading so it can be sorted.
    @State private var isLoadingAllSongs = false
    /// What Find in Playlist looks for: a song shows while every word of
    /// it is in its title, artist or album.
    @State private var songQuery = ""
    /// The Find in Playlist bar is up: pulled down from the top of the
    /// list, or opened from the toolbar's magnifying glass.
    @State private var showsSongSearch = false
    @FocusState private var isSongSearchFocused: Bool
    /// The rest of the playlist is loading so all of it can be searched.
    @State private var isLoadingSearch = false

    /// Proxies the view's existing `tracks` usage onto the coordinator (the source of truth),
    /// so native undo/redo mutations are reflected in the UI.
    private var tracks: [PlayableContent] {
        get { editor.tracks }
        nonmutating set { editor.tracks = newValue }
    }

    var maxHeight: Double {
        usesPadLayout ? 400 : 340
    }

    /// For a non-Sonos service playlist, whether the user can actually edit it (owns it or it's
    /// collaborative). Confirmed at load — streaming services let you browse playlists you can't edit.
    @State private var serviceEditable = false

    /// `serviceEditable` is true for Sonos (always yours) and ownership-confirmed for streaming, so
    /// these are just the capability AND that flag.
    private var isEditablePlaylist: Bool {
        playableContent.isRemovablePlaylist && serviceEditable
    }

    private var canReorderTracks: Bool {
        playableContent.isReorderablePlaylist && serviceEditable
    }

    /// A downloaded album or playlist from the on-device library
    /// (`OnDeviceLibrary`): its songs are the ones here, read from the
    /// device, so the page opens with no network and keeps up as downloads
    /// come and go. It has no server's album or playlist behind it to
    /// download, open a menu on, edit, or go to the artist of.
    private var isOnDevice: Bool {
        OnDeviceLibrary.isContainer(playableContent)
    }

    /// Whether the playlist's songs can be searched (Find in Playlist) and
    /// listed in another order, both put together here: a playlist that
    /// comes whole (Subsonic, Files, an Apple Music catalog playlist, one
    /// on the device) or says how many songs it has (Plex, an Apple Music
    /// library playlist), so every page can be loaded first. A playlist
    /// that only says whether there's more would sort and search the
    /// pages in hand.
    private var sortsSongs: Bool {
        guard playableContent.content.type.isPlaylist else { return false }
        return isOnDevice || [.plex, .apple, .subsonic, .files].contains(playableContent.content.service)
    }

    /// The orders on offer: dates, plays and ratings only for Plex, whose
    /// songs carry them.
    private var songSortOptions: [PlaylistSongSort] {
        PlaylistSongSort.options(withLibraryDetails: playableContent.content.service == .plex && !isOnDevice)
    }

    /// Find in Playlist has something to look for.
    private var isFindingSongs: Bool {
        !songQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One row of the song list: the song, where it sits in the playlist
    /// (what edits, selection and paging address) and the number it shows.
    private struct SongRow: Identifiable {
        let number: Int
        let index: Int
        let song: PlayableContent
        var id: String { song.trackID }
    }

    /// The songs as listed: the playlist's order, or `sortedOrder`'s. What
    /// plays from a row, and the number it shows.
    private var listedRows: [SongRow] {
        let tracks = tracks
        let order = sortedOrder ?? Array(tracks.indices)
        return order.enumerated().compactMap { offset, index in
            // An order a step behind an edit is put right by `onChange`.
            guard tracks.indices.contains(index) else { return nil }
            return SongRow(number: offset + 1, index: index, song: tracks[index])
        }
    }

    /// The rows shown: `listedRows`, narrowed to Find in Playlist's matches
    /// while it has something to look for. Each keeps its number in the
    /// whole list, so a match says where it is, and a tap plays on from
    /// there through the rest of the list, not just the matches.
    private var songRows: [SongRow] {
        let rows = listedRows
        let words = songQuery.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return rows }
        return rows.filter { Self.isMatch($0.song, for: words) }
    }

    /// Every word somewhere in the song's title, artist or album, case and
    /// accents aside: "adele hello" finds Hello by Adele.
    private static func isMatch(_ song: PlayableContent, for words: [Substring]) -> Bool {
        let fields = [song.title, song.metadata?.artist, song.metadata?.album].compactMap { $0 }
        return words.allSatisfy { word in
            fields.contains { $0.localizedStandardContains(word) }
        }
    }

    /// The book's page for an album page opened on a book or one of its
    /// files (the player's title on a book), not an album of its files. It
    /// stays the book's while the book is the one loaded or the one last
    /// left (`AudiobookPlayer.book(containing:)`).
    var body: some View {
        if let book = AudiobookPlayer.shared.book(containing: playableContent) {
            AudiobookDetailView(book: book)
        } else {
            albumPage
        }
    }

    @ViewBuilder
    private var albumPage: some View {
        @Bindable var router = router
        // Read as `body` runs, so a pick runs it again: what only the
        // toolbar's builder reads doesn't, and the sort menu's checkmarks
        // and spinner would lag behind.
        let _ = (songSort, songSortReversed, isLoadingAllSongs)
        let rows = songRows
        List(selection: $selection) {
            // While Find in Playlist has something to look for, the matches
            // lead, right under its bar: below the cover and its buttons
            // they'd be behind the keyboard, and typing would seem to do
            // nothing.
            if !isFindingSongs {
                artworkSection
            }
            ForEach(rows) { row in
                let index = row.index
                let item = row.song
                VStack {
                    PlayableContentView(item: item,
                                        parent: content ?? playableContent,
                                        hideArtwork: content?.content.type == .album,
                                        hideContentType: true,
                                        index: row.number,
                                        // Only some of a downloaded album may be
                                        // here: each shows its place on the album.
                                        number: isOnDevice && playableContent.content.type == .album ? item.metadata?.position : nil,
                                        dismissOnComplete: true,
                                        total: totalSongs ?? tracks.count,
                                        onRemoveFromPlaylist: isEditablePlaylist ? { removeTrack(at: index) } : nil,
                                        playAction: sortedOrder == nil ? nil : { playListed(from: row.number - 1) })
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
                    let nearEnd = row.number - 1 >= tracks.count - Self.prefetchThreshold
                    if nearEnd && isLoadingMore && hasMore {
                        await updateTracks(offset: loadedItemCount)
                    }
                }
                .listRowBackground(Color.white.opacity(0.001))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            // Moving a song means something only in the playlist's own
            // order, with every song in it showing.
            .onMove(perform: canReorderTracks && sortedOrder == nil && !isFindingSongs ? move : nil)
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
            } else if isFindingSongs {
                // The matches so far show while the rest of the playlist
                // loads to be searched.
                if isLoadingSearch {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.white.opacity(0.001))
                } else if rows.isEmpty {
                    ContentUnavailableView.search(text: songQuery.trimmingCharacters(in: .whitespacesAndNewlines))
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
        // The cover runs up under the navigation bar; the matches keep
        // below it and the Find in Playlist bar.
        .ignoresSafeArea(edges: isFindingSongs ? [] : .top)
        .onScrollOffset(exceeds: 300, set: $showNavigationTitle)
        // Pulled down past the top, as Music's Find in Playlist is: up
        // as the pull gets far enough, the cursor in it once it's let go.
        .onPullDown(beyond: 60) {
            showSongSearch()
        } onRelease: {
            if showsSongSearch { isSongSearchFocused = true }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showsSongSearch) { _, shows in shows }
        .scrollEdgeEffectHidden26(!showNavigationTitle && !isFindingSongs)
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            if isEditablePlaylist && !selection.isEmpty {
                Button(role: .destructive) {
                    editor.removeSelected(Array(selection))
                    selection.removeAll()
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
        // Under the navigation bar, over the cover and the songs: the list
        // runs up under both, so it doesn't move as the bar comes and goes,
        // until there's something to look for (`ignoresSafeArea` above).
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsSongSearch {
                songSearchBar
            }
        }
        .task(id: isFindingSongs && isLoaded) {
            // Every song, so a match on a page not yet loaded isn't missed:
            // once the first page has said how many there are.
            guard isFindingSongs, isLoaded else { return }
            isLoadingSearch = true
            await loadAllTracks()
            isLoadingSearch = false
        }
        .onChange(of: songQuery) {
            // Remove (N) takes only songs that show.
            guard !selection.isEmpty, isFindingSongs else { return }
            selection.formIntersection(songRows.map(\.index))
        }
        .onChange(of: isSongSearchFocused) { _, focused in
            // Put away once it's left with nothing in it (the keyboard
            // dismissed by a scroll, a song tapped).
            guard !focused, songQuery.isEmpty else { return }
            withAnimation(.smooth) { showsSongSearch = false }
        }
        .task {
            editor.configure(playlist: playableContent)
            // Point the Catalyst Edit-menu bridge at this editor so native Edit ▸ Undo/Redo can
            // drive playlist undo through the responder chain.
            PlaylistUndoMenuBridge.shared.editor = editor
            // Resolve edit permission independently so the Edit affordance isn't gated on track
            // loading (instant for Sonos, an ownership lookup for streaming).
            Task { serviceEditable = isOnDevice ? false : await confirmServiceEditable() }
            await updateTracks(offset: loadedItemCount)
            restoreSongSort()
            if songSort != .playlistOrder {
                await applySongSort()
            }
        }
        .onChange(of: isOnDevice ? OnDeviceLibrary.changeToken : 0) {
            loadOnDeviceTracks()
        }
        .onChange(of: tracks) { _, tracks in
            // A song removed (or put back by Undo) while sorted: sort again
            // rather than point at rows that have moved.
            guard sortedOrder != nil, songSort != .playlistOrder else { return }
            sortedOrder = songSort.order(of: tracks, reversed: songSortReversed)
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
                // The playlist's name, as its header is put away while it's
                // searched.
                .opacity(showNavigationTitle || isFindingSongs ? 1 : 0)
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                if sortsSongs {
                    // The pull down's bar, for a mouse, a keyboard and
                    // anyone who doesn't know to pull.
                    Button {
                        revealSongSearch()
                    } label: {
                        Label("Find in Playlist", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    songSortMenu
                }
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
                    // Not while Find in Playlist is typed in: a bare E
                    // would turn Edit on instead of going in the field.
                    .keyboardShortcut(isSongSearchFocused ? nil : KeyboardShortcut("e", modifiers: []))
                }
            }
        }
        .animation(.smooth, value: showNavigationTitle)
    }
    
    /// The hero image, decoded no larger than it is drawn. The header shows
    /// at most ~400pt and blurs it, but the URL is the full-size art — for
    /// Plex the original file, often several megapixels — and a 100pt blur
    /// over a bitmap that size costs Core Animation offscreen buffers many
    /// times the image, which is where this screen's memory jumps came from.
    private var heroRequest: ImageRequest {
        var request = ImageRequest(url: content?.artwork)
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 800)
        return request
    }

    @ViewBuilder
    private var artworkSection: some View {
        Color.clear.overlay {
            // One image for the glow and the cover, so both land in the same
            // frame. A plain request for the glow beside the blurred one
            // showed the glow alone until the blur was worked out, then the
            // cover popped in, and kept two copies of the cover in the caches.
            LazyImage(request: heroRequest.withBlurredFoot) { phase in
                if let image = phase.image {
                    ZStack {
                        image
                            .resizable()
                            .scaledToFit()
                            .blur(radius: 100)
                            .frame(maxWidth: .infinity, maxHeight: maxHeight)
                        image
                            .resizable()
                            .scaledToFill()
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
                if isOnDevice {
                    Text(content?.metadata?.artist ?? "")
                        .bold()
                        .lineLimit(1)
                } else {
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
                }
                
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
                
                if let content, !isOnDevice {
                    // Keep the whole album or playlist on this device — the
                    // same action as the ellipsis menu's This Device ›
                    // Download, one tap from the header.
                    ContainerDownloadButton(item: content)

                    Menu {
                        PlayableMenuView(item: content)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("More Options")
                    .buttonBorderShape(.circle)
                    .contentShape(.rect)
                    .glassButton()
                } else if isOnDevice {
                    // All here: the button says so, with Remove behind it.
                    OnDeviceDownloadButton(container: playableContent)
                }
            }
            .bold()
            .fontDesign(.rounded)
            // Dark glass in Light Mode too: the buttons sit on the cover,
            // under the header's dark fade, where light glass washed out.
            .environment(\.colorScheme, .dark)
        }
        .fontDesign(.rounded)
        .foregroundStyle(.white)
    }
    
    private func play(_ playMode: PlayMode = .normal) {
        // Sorted, Play plays the songs as listed; Shuffle shuffles the
        // playlist, where the order doesn't matter.
        if playMode == .normal, sortedOrder != nil {
            playListed(from: 0)
            return
        }
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
                await PlayDestinationRouter.play(currentContent, position: defaultPosition, shuffle: playMode.contains(.shuffle), queue: queue)
                return
            }

            try await queue(group, defaultPosition)
        }
    }
    
    /// Find in Playlist: the field, with Clear inside it while there's
    /// something in it, and Close beside it, which clears it too.
    private var songSearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find in Playlist", text: $songQuery)
                    .focused($isSongSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { isSongSearchFocused = false }
                if !songQuery.isEmpty {
                    Button {
                        songQuery = ""
                        isSongSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCapsule26()

            Button {
                closeSongSearch()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .frame(width: 22, height: 22)
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close Find in Playlist")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Puts up Find in Playlist, without the cursor: a pull shows it while
    /// the finger is still down, and focuses it as it lets go.
    private func showSongSearch() {
        guard sortsSongs, !showsSongSearch else { return }
        withAnimation(.smooth) { showsSongSearch = true }
    }

    /// Puts up Find in Playlist and puts the cursor in it, or only the
    /// cursor when it's already up (the toolbar's button).
    private func revealSongSearch() {
        guard sortsSongs else { return }
        showSongSearch()
        // Once the field is in the window: in the pass that adds it there's
        // nothing to focus yet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            isSongSearchFocused = true
        }
    }

    /// Clears Find in Playlist and puts it away, every song showing again.
    private func closeSongSearch() {
        isSongSearchFocused = false
        songQuery = ""
        withAnimation(.smooth) { showsSongSearch = false }
    }

    /// Sort By and, for an order that has one, its direction — the same
    /// menu as the library's lists.
    private var songSortMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { songSort },
                set: { sort in
                    guard sort != songSort else { return }
                    songSort = sort
                    // Each order starts in its own natural direction; the
                    // Order picker is there to flip it.
                    songSortReversed = false
                    rememberSongSort()
                    Task { await applySongSort() }
                }
            )) {
                ForEach(songSortOptions) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.inline)

            if songSort.isReversible {
                Picker("Order", selection: Binding(
                    get: { songSortReversed },
                    set: { reversed in
                        guard reversed != songSortReversed else { return }
                        songSortReversed = reversed
                        rememberSongSort()
                        Task { await applySongSort() }
                    }
                )) {
                    Text(songSort.ascendingLabel).tag(false)
                    Text(songSort.descendingLabel).tag(true)
                }
                .pickerStyle(.inline)
            }
        } label: {
            if isLoadingAllSongs {
                ProgressView()
            } else {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
            }
        }
        .accessibilityLabel("Sort")
    }

    /// Lists the songs in `songSort`'s order, loading the pages still to
    /// come first: sorting only the pages in hand would move songs about as
    /// the rest arrived, so the playlist's order stays until every song is
    /// in.
    private func applySongSort() async {
        guard songSort != .playlistOrder else {
            sortedOrder = nil
            return
        }
        isLoadingAllSongs = true
        await loadAllTracks()
        isLoadingAllSongs = false
        // Back to the playlist's order while the songs were loading.
        guard !Task.isCancelled, songSort != .playlistOrder else { return }
        sortedOrder = songSort.order(of: tracks, reversed: songSortReversed)
    }

    /// Every page still to come, one after another.
    private func loadAllTracks() async {
        while let total = totalSongs, loadedItemCount < total, !Task.isCancelled {
            // The list's own paging may have a page on its way: wait it out
            // rather than skip it.
            if isFetchingPage {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            let loaded = loadedItemCount
            await updateTracks(offset: loadedItemCount)
            // A page that failed or came back empty: stop, rather than ask
            // for it again for ever.
            guard loadedItemCount > loaded else { break }
        }
    }

    private var songSortKey: String { "playlistSongSort.\(playableContent.id)" }

    private func restoreSongSort() {
        guard sortsSongs,
              let raw = UserDefaults.standard.string(forKey: songSortKey),
              let sort = PlaylistSongSort(rawValue: raw),
              songSortOptions.contains(sort) else { return }
        songSort = sort
        songSortReversed = UserDefaults.standard.bool(forKey: songSortKey + ".reversed")
    }

    private func rememberSongSort() {
        // The playlist's own order is the default, so it needs no entry.
        guard songSort != .playlistOrder else {
            UserDefaults.standard.removeObject(forKey: songSortKey)
            UserDefaults.standard.removeObject(forKey: songSortKey + ".reversed")
            return
        }
        UserDefaults.standard.set(songSort.rawValue, forKey: songSortKey)
        UserDefaults.standard.set(songSortReversed, forKey: songSortKey + ".reversed")
    }

    /// Plays the songs as they're listed, from the `start`th on. A sorted
    /// playlist isn't the playlist's own order, so a speaker gets the songs
    /// rather than the playlist, and this device the list.
    private func playListed(from start: Int) {
        // The whole list, a match found in it included: `start` is a
        // row's place in it.
        let listed = listedRows.map(\.song)
        guard listed.indices.contains(start) else { return }
        let songs = listed[start...].filter(\.isPlayable)
        guard !songs.isEmpty else { return }
        Task { @MainActor in
            let currentContent = content ?? playableContent
            let defaultPosition = QueuePosition.defaultPosition(
                for: currentContent.content.type,
                replaceQueueByDefault: replaceQueueByDefault
            )
            let queue: ((GroupRoom, QueuePosition) async throws -> Void) = { [songs, currentContent] group, selectedPosition in
                // In the order shown, so not shuffled.
                await SonosService.shared.setPlayMode(group.ip, mode: .normal)
                group.playMode = .normal
                switch selectedPosition {
                case .replace:
                    try await SonosService.shared.queue(contents: songs, group: group, position: .replace, startIndex: 0)
                case .now:
                    try await SonosService.shared.playNext(songs, on: group)
                default:
                    try await SonosService.shared.queue(contents: songs, group: group, position: selectedPosition)
                }
                playHistoryService.record(currentContent)
                Router.main.show(destination: .player(groupID: group.coordinatorID))
            }

            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(songs, position: defaultPosition, from: currentContent, queue: queue)
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

        if isOnDevice {
            loadOnDeviceTracks()
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
        case (.album, .subsonic):
            newTracks = await musicSearchService.lookupSubsonicAlbumTracks(id: playableContent.content.id)
            isLoadingMore = false
        case (.playlist, .subsonic):
            newTracks = await musicSearchService.lookupSubsonicPlaylistTracks(id: playableContent.content.id)
            isLoadingMore = false
        case (.track, .subsonic):
            let albumID: String?
            if let existing = playableContent.metadata?.albumID {
                albumID = existing
            } else {
                albumID = await musicSearchService.lookupSubsonicTrack(with: playableContent.content.id)?.metadata?.albumID
            }
            guard let albumID else { return }
            // One getAlbum response carries the album and its tracks.
            guard let result = await musicSearchService.lookupSubsonicAlbumWithTracks(id: albumID) else { return }
            content = result.album
            newTracks = result.tracks
            isLoadingMore = false
        case (.album, .files):
            await FilesLibraryService.shared.scanIfNeeded()
            newTracks = FilesLibraryService.shared.albumTracks(albumID: playableContent.content.id)
            isLoadingMore = false
        case (.playlist, .files):
            await FilesLibraryService.shared.scanIfNeeded()
            newTracks = FilesLibraryService.shared.playlistTracks(playlistID: playableContent.content.id)
            isLoadingMore = false
        case (.track, .files):
            await FilesLibraryService.shared.scanIfNeeded()
            let files = FilesLibraryService.shared
            guard let albumID = playableContent.metadata?.albumID
                    ?? files.track(id: playableContent.content.id)?.metadata?.albumID,
                  let album = files.album(id: albumID) else { return }
            content = album
            newTracks = files.albumTracks(albumID: albumID)
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
    
    /// The songs of a downloaded album that are on the device, in track
    /// order.
    private func loadOnDeviceTracks() {
        guard isOnDevice else { return }
        let hadTracks = !tracks.isEmpty
        tracks = OnDeviceLibrary.tracks(inContainer: playableContent) ?? []
        loadedItemCount = tracks.count
        isLoadingMore = false
        // Its last song removed, from the header's button or a row's menu:
        // there's no album or playlist here any more to show.
        if hadTracks, tracks.isEmpty {
            dismiss()
        }
    }

    func appendTracksAvoidingDuplicates(newTracks: [PlayableContent], to tracks: inout [PlayableContent]) {
        // Seed counts from the already-loaded tracks in a single pass, then update as we
        // append. Avoids re-scanning the whole (growing) tracks array for every new row,
        // which otherwise makes each page append slower the further you paginate.
        var idCounts: [String: Int] = tracks.reduce(into: [:]) { counts, track in
            counts[track.id, default: 0] += 1
        }
        var rowIDs = Set(tracks.map(\.trackID))

        for var newTrack in newTracks {
            let originalID = newTrack.id
            let existingCount = idCounts[originalID, default: 0]

            if existingCount > 0 {
                // A library song's position is its track number, which the
                // copy's count can land on: step past a row id in use.
                var position = existingCount + 1
                newTrack.metadata?.position = position
                while newTrack.metadata != nil, rowIDs.contains(newTrack.trackID) {
                    position += 1
                    newTrack.metadata?.position = position
                }
            }

            idCounts[originalID] = existingCount + 1
            rowIDs.insert(newTrack.trackID)
            tracks.append(newTrack)
        }
    }
    
    /// Removes the track at `index` from the playlist. The editor dispatches to Sonos or the
    /// streaming service and keeps its track list in sync.
    private func removeTrack(at index: Int) {
        editor.removeTrack(at: index)
    }

    /// Whether the playlist is editable: Sonos playlists always are; streaming playlists require
    /// confirmed ownership (owned/collaborative).
    private func confirmServiceEditable() async -> Bool {
        if playableContent.isSonosPlaylist { return true }
        guard playableContent.isEditableServicePlaylist else { return false }
        return await musicSearchService.canEditServicePlaylist(playableContent)
    }

    private func move(from source: IndexSet, to destination: Int) {
        editor.moveTrack(from: source, to: destination, playlist: playableContent)
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

