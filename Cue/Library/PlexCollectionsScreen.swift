import Defaults
import Glur
import MusicSearchKit
import Nuke
import NukeUI
import SonosKit
import SwiftUI

/// The Plex library's collections — albums (or artists, or songs) grouped on
/// the server — as a grid of their covers or a list.
struct PlexCollectionsScreen: View {
    @Environment(Router.self) private var router
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @AppStorage(Defaults.AppStorageKeys.plexCollectionsLayout) private var layout: PlayableListLayout = .grid

    @State private var isLoading = false
    /// A page is on its way; no other is asked for meanwhile.
    @State private var isLoadingMore = false


    private var hasMore: Bool {
        plexBrowseService.collections.count < (plexBrowseService.collectionCount ?? 0)
    }

    var body: some View {
        @Bindable var router = router

        // A real container, not a `Group`, so flipping the layout keeps the
        // task, toolbar and refresh action rather than rebuilding them with
        // the branch (see `AudibleBrowseScreen`).
        VStack(spacing: 0) {
            if layout == .grid {
                grid
            } else {
                list
            }
        }
        .refreshable {
            await plexBrowseService.updateCollections()
        }
        .overlay {
            if isLoading, plexBrowseService.collections.isEmpty {
                ProgressView()
            } else if plexBrowseService.collectionCount == 0 {
                // Only once the server has answered, not before the first page.
                ContentUnavailableView(
                    "No Collections",
                    systemImage: "square.stack.3d.up",
                    description: Text("Collections you make in Plex, or with Add to Collection on an album, show up here.")
                )
            }
        }
        .fontDesign(.rounded)
        .navigationTitle("Collections")
        // Presented from here, as MediaDetailView does: left to the stack's
        // presenter, a sheet asked for from a pushed screen's menu (picking
        // a room to play on) waited until the screen changed.
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Pull to refresh isn't there on the Mac.
                Button {
                    Task { await plexBrowseService.updateCollections() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                // The icon is the layout a tap gives you, the way a button
                // names what it does.
                Button("Show as \(layout.other.label)", systemImage: layout.other.systemImage) {
                    withAnimation(.smooth) { layout = layout.other }
                }
                .labelStyle(.iconOnly)
            }
        }
        .task {
            // The browse screen has usually loaded the first page already.
            // Reloading it here would also run on the way back from a
            // collection, and drop every page scrolled to since.
            guard plexBrowseService.collections.isEmpty else { return }
            isLoading = true
            await plexBrowseService.updateCollections()
            isLoading = false
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: CoverGridTile.columns, spacing: CoverGridTile.divider) {
                ForEach(plexBrowseService.collections) { collection in
                    NavigationLink(value: RouterDestination.folderBrowse(item: collection, title: collection.title)) {
                        CoverGridTile(item: collection)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        PlayableMenuView(item: collection)
                    }
                    .onAppear { loadMoreIfNeeded(after: collection) }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(plexBrowseService.collections) { collection in
                NavigationLink(value: RouterDestination.folderBrowse(item: collection, title: collection.title)) {
                    PlexCollectionRow(collection: collection)
                }
                .contextMenu {
                    PlayableMenuView(item: collection)
                }
                // As tight as the album rows (`PlayableContentView`).
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 20))
                .listRowSeparator(.hidden)
                .onAppear { loadMoreIfNeeded(after: collection) }
            }
        }
        .listStyle(.plain)
    }

    /// Asks for the next page when the last collection appears, one page at
    /// a time.
    private func loadMoreIfNeeded(after collection: PlayableContent) {
        guard !isLoadingMore, hasMore, plexBrowseService.collections.last == collection else { return }
        isLoadingMore = true
        Task {
            await plexBrowseService.updateCollections(offset: plexBrowseService.collections.count)
            isLoadingMore = false
        }
    }
}

/// One Plex collection, laid out like an album's page: its cover full width
/// at the top with the title, Play and Shuffle over it, then what it holds
/// as full-width cards or a list. On a server the account owns, the •••
/// button edits it: remove and reorder what it holds, change the order it's
/// kept in, rename it or delete it. A smart collection is a saved filter,
/// so it can be renamed or deleted but not edited item by item.
struct PlexCollectionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Environment(AlertService.self) private var alertService
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @AppStorage(Defaults.AppStorageKeys.plexCollectionLayout) private var layout: PlayableListLayout = .grid

    let collection: PlayableContent

    @State private var items: [PlayableContent] = []
    /// The whole collection has been read at least once.
    @State private var hasLoaded = false
    @State private var isLoading = false
    /// The collection as the server has it now; nil until read.
    @State private var details: PlexCollection?
    @State private var title: String
    @State private var order: PlexCollectionSort = .releaseDate
    @State private var editMode: EditMode = .inactive
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false
    /// The change last sent to the server. Each waits on the one before, so
    /// two quick moves land in the order they were made.
    @State private var lastChange: Task<Void, Never>?
    /// Past the cover, so the title shows in the bar instead.
    @State private var showNavigationTitle = false

    /// The cover's height, as on an album's page.
    private var heroHeight: Double {
        UIDevice.current.userInterfaceIdiom == .phone ? 340 : 400
    }

    /// The cover's width. Edge to edge on a phone, to line up with the grid
    /// under it: the album page's 400 pt cap left it inset on a phone wider
    /// than that. Capped on an iPad, where the full width would crop the
    /// cover to a strip; the blurred copy fills the sides.
    private var heroCoverWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? .infinity : 400
    }

    init(collection: PlayableContent) {
        self.collection = collection
        _title = State(initialValue: collection.title)
    }

    /// Renaming and deleting: anything in the library is the owner's to
    /// change.
    private var canManage: Bool {
        plexBrowseService.canManageCollections == true && details != nil
    }

    /// Removing and moving items, which a smart collection doesn't have.
    private var canEditItems: Bool {
        canManage && details?.smart == false
    }

    private var subtitle: String {
        details?.itemCountLabel ?? collection.subtitle
    }

    var body: some View {
        @Bindable var router = router

        // One container for both layouts (see `PlexCollectionsScreen`). The
        // list while editing, since only it can delete and move rows.
        VStack(spacing: 0) {
            if layout == .grid, !editMode.isEditing, !items.isEmpty {
                grid
            } else {
                list
            }
        }
        // The cover runs up under the bar, as on an album's page.
        .ignoresSafeArea(edges: .top)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .onScrollOffset(exceeds: heroHeight - 40, set: $showNavigationTitle)
        .scrollEdgeEffectHidden26(!showNavigationTitle)
        .refreshable {
            await loadDetails()
            await reload()
        }
        .overlay {
            if isLoading, items.isEmpty {
                ProgressView()
            }
        }
        .fontDesign(.rounded)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        // Presented from here, as MediaDetailView does: left to the stack's
        // presenter, Add to Collection (or a room to play on) asked for from
        // this screen's menus waited until the screen changed.
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .animation(.smooth, value: showNavigationTitle)
        .alert("Rename Collection", isPresented: $showRename) {
            TextField("Collection name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
        .confirmationDialog("Delete “\(title)”?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) { delete() }
        } message: {
            Text("What it holds stays in your Plex library.")
        }
        .task {
            // The order first, since it decides the items' order.
            if details == nil {
                await loadDetails()
            }
            if items.isEmpty {
                await reload()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(title)
                    .bold()
                    .multilineTextAlignment(.center)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .bold()
                }
            }
            .fontDesign(.rounded)
            .opacity(showNavigationTitle ? 1 : 0)
        }

        if editMode.isEditing {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    withAnimation { editMode = .inactive }
                }
                .bold()
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Show as \(layout.other.label)", systemImage: layout.other.systemImage) {
                    withAnimation(.smooth) { layout = layout.other }
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var manageMenu: some View {
        if canEditItems {
            Button {
                withAnimation { editMode = .active }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }

        Button {
            renameText = title
            showRename = true
        } label: {
            Label("Rename…", systemImage: "textformat")
        }

        if canEditItems {
            // Plex's own Collection Order. Items can only be dragged into
            // place in Custom, so the order being edited is the server's.
            Picker("Order", selection: orderSelection) {
                Text("Release Date").tag(PlexCollectionSort.releaseDate)
                Text("Alphabetical").tag(PlexCollectionSort.alphabetical)
                Text("Custom").tag(PlexCollectionSort.custom)
            }
            .pickerStyle(.inline)
        }

        Divider()

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Collection…", systemImage: "trash")
        }
    }

    private var orderSelection: Binding<PlexCollectionSort> {
        Binding(
            get: { order },
            set: { setOrder($0) }
        )
    }

    private var grid: some View {
        ScrollView {
            VStack(spacing: CoverGridTile.divider) {
                hero

                LazyVGrid(columns: CoverGridTile.columns, spacing: CoverGridTile.divider) {
                    ForEach(items) { item in
                        NavigationLink(value: destination(for: item)) {
                            CoverGridTile(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            PlayableMenuView(item: item)
                        }
                    }
                }
            }
        }
    }

    /// Where an item opens: an artist's page for an artist, an album's
    /// page for an album, or for a song, the album it's on.
    private func destination(for item: PlayableContent) -> RouterDestination {
        item.content.type.isArtist
            ? .artistDetail(content: item, group: selectedGroupService.group)
            : .mediaDetail(content: item, group: selectedGroupService.group)
    }

    private var list: some View {
        List {
            hero
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
                .deleteDisabled(true)
                .moveDisabled(true)

            if editMode.isEditing, order != .custom {
                Text("Choose Custom order in the ••• menu to drag items into place.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .deleteDisabled(true)
                    .moveDisabled(true)
            }

            ForEach(items) { item in
                Group {
                    if editMode.isEditing {
                        // Mid-edit a row is only something to delete or
                        // drag: no way into the album, no chevron, no menu.
                        PlayableContentView(item: item, hideDetails: true, hideContentType: true)
                            .allowsHitTesting(false)
                    } else {
                        PlayableContentView(item: item, hideContentType: true)
                    }
                }
            }
            .onDelete(perform: canEditItems ? remove : nil)
            .onMove(perform: canEditItems && order == .custom ? move : nil)

            // Only once the collection has come back with nothing — not
            // before it has, nor after a read that failed.
            if items.isEmpty, hasLoaded, !isLoading {
                ContentUnavailableView(
                    "Empty Collection",
                    systemImage: "square.stack.3d.up",
                    description: Text("There's nothing in this collection yet.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
    }

    /// The cover, decoded no larger than it is drawn, as on an album's page:
    /// for Plex the URL is the original file, and a blur over a bitmap that
    /// size costs far more than the image.
    private var heroRequest: ImageRequest {
        var request = ImageRequest(url: collection.artwork)
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 800)
        return request
    }

    /// The cover, drawn as `MediaDetailView` draws an album's: a blurred
    /// copy behind for the glow, the cover itself fading into it at the
    /// bottom under the title and buttons, stretching as the page is pulled
    /// down.
    private var hero: some View {
        Color.clear.overlay {
            ZStack {
                LazyImage(request: heroRequest) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .blur(radius: 100)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: heroHeight)
                LazyImage(request: heroRequest) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .glur(radius: 30, offset: 0.6, interpolation: 0.4, direction: .down, noise: 0.1, drawingGroup: false)
                            .frame(maxWidth: heroCoverWidth, maxHeight: heroHeight)
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
            heroOverlay
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
        .frame(height: heroHeight)
    }

    private var heroOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title)
                .fontWeight(.black)
                .minimumScaleFactor(0.3)
                .allowsTightening(true)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .bold()
                    .padding(.bottom, 4)
            }
            if !editMode.isEditing {
                HStack(spacing: 12) {
                    Button {
                        play(.normal)
                    } label: {
                        Text("\(Image(systemName: "play.fill")) Play")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                    .glassButton()
                    .foregroundStyle(.primary)
                    .disabled(items.isEmpty)

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
                    .disabled(items.isEmpty)

                    if canManage {
                        Menu {
                            manageMenu
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
            }
        }
        .fontDesign(.rounded)
        .foregroundStyle(.white)
    }

    private func play(_ mode: PlayMode) {
        // Everything's on screen already — no need to ask for it again.
        let loaded = hasLoaded ? items : nil
        PlexCollectionPlayer.play(collection, items: loaded, mode: mode, selectedGroupService: selectedGroupService)
    }

    // MARK: - Loading

    /// The whole collection again, in its order. What's on screen stays if
    /// it fails.
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let loaded = await plexBrowseService.items(of: collection, in: order) else { return }
        items = loaded
        hasLoaded = true
    }

    /// The collection as the server has it now, and whether this account
    /// may change it.
    private func loadDetails() async {
        if plexBrowseService.canManageCollections == nil {
            await plexBrowseService.checkCollectionAccess()
        }
        guard let fresh = await plexBrowseService.details(of: collection) else { return }
        details = fresh
        title = fresh.title
        // Only when Plex says: a collection left in its default order may
        // not carry the field, and reading that as Release Date would undo
        // the order just picked.
        if let sort = fresh.collectionSort.flatMap({ PlexCollectionSort(rawValue: $0) }) {
            order = sort
        }
    }

    // MARK: - Editing

    private func remove(at offsets: IndexSet) {
        let removed = offsets.map { items[$0] }
        withAnimation { items.remove(atOffsets: offsets) }
        for item in removed {
            send(failure: "Couldn’t remove \(item.title)") {
                await plexBrowseService.remove(item, from: collection)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let moved = items[from]
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        guard let index = reordered.firstIndex(of: moved) else { return }
        // Plex places an item after another, or at the front.
        let previous = index > 0 ? reordered[index - 1] : nil
        items = reordered
        send(failure: "Couldn’t move \(moved.title)") {
            await plexBrowseService.move(moved, after: previous, in: collection)
        }
    }

    /// Sets the order the collection is kept in. Picking the order already
    /// ticked sends it again, rather than doing nothing.
    private func setOrder(_ sort: PlexCollectionSort) {
        let previous = order
        order = sort
        send(failure: "Plex didn’t change the order") {
            guard await plexBrowseService.setOrder(sort, for: collection) else {
                order = previous
                return false
            }
            // Read back: a route the server answers without keeping the
            // change would otherwise look like it worked.
            if let kept = await plexBrowseService.details(of: collection)?.collectionSort,
               kept != sort.rawValue {
                order = previous
                return false
            }
            await reload()
            return true
        }
    }

    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != title else { return }
        let previous = title
        title = name
        send(failure: "Couldn’t rename \(previous)") {
            guard await plexBrowseService.rename(collection, to: name) else {
                title = previous
                return false
            }
            return true
        }
    }

    private func delete() {
        Task {
            await lastChange?.value
            if await plexBrowseService.delete(collection) {
                dismiss()
            } else {
                alertService.showAlert(with: "Couldn’t delete \(title)", imageName: "exclamationmark.triangle")
            }
        }
    }

    /// Sends a change to the server once the ones before it are done. The
    /// screen already shows it; if the server refuses, an alert says so
    /// and the collection is read back as the server has it.
    private func send(failure: String, _ change: @escaping () async -> Bool) {
        let previous = lastChange
        lastChange = Task {
            await previous?.value
            if await change() {
                await loadDetails()
            } else {
                alertService.showAlert(with: failure, imageName: "exclamationmark.triangle")
                await reload()
                await loadDetails()
            }
        }
    }
}

/// A collection as a list row: cover, name and count.
private struct PlexCollectionRow: View {
    let collection: PlayableContent

    var body: some View {
        HStack(spacing: 12) {
            ContentArtworkView(content: collection, showMusicSource: false)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .lineLimit(1)
                if !collection.subtitle.isEmpty {
                    Text(collection.subtitle)
                        .font(.footnote)
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// A cell of an edge-to-edge cover grid: the cover, square-cornered, and
/// under it the title and subtitle on the cover's own colours carried on
/// down (the player's mesh background, drawn small). The grid's 1 pt
/// spacing draws the dividers between cells.
private struct CoverGridTile: View {
    /// Two across on a phone, so the text under each cover has room; more
    /// on an iPad.
    static let columns = [GridItem(.adaptive(minimum: 150), spacing: divider)]
    static let divider: CGFloat = 1

    let item: PlayableContent

    @State private var mesh: ArtworkMesh?

    /// Dark text on a light cover's colours, white on the rest, and the
    /// usual text colour until the colours are in.
    private var textColor: Color {
        mesh.map { $0.isLight ? Color.black : Color.white } ?? Color.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContentArtworkView(content: item, showMusicSource: false, preferredSize: 200, cornerRadius: 0)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline)
                    .bold()
                Text(item.subtitle)
                    .font(.caption)
                    .opacity(0.8)
            }
            // Every cell the same height, so a row's backgrounds meet.
            .lineLimit(1, reservesSpace: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(textColor)
        }
        .background {
            // Stretched over the whole cell, so the band under the cover
            // shows the bottom of the gradient: the colours the cover ends on.
            if let mesh {
                Image(uiImage: mesh.image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color(uiColor: .secondarySystemBackground)
            }
        }
        .contentShape(.rect)
        .task(id: item.imageKey) {
            mesh = await ArtworkMesh.load(from: item.thumbnail ?? item.artwork, key: item.imageKey)
        }
    }
}

/// Plays a Plex collection. Sonos has no URI for one, so what it holds is
/// queued in one go instead, the way an artist's discography is: in the
/// collection's order, replacing the queue and playing as soon as the first
/// item is in. With no speaker in context it goes where Play goes
/// (`PlayDestinationRouter`), so a collection of albums plays on this device
/// too.
@MainActor
enum PlexCollectionPlayer {
    /// - Parameter items: Everything the collection holds, when the caller
    ///   already has it; nil to fetch it first.
    static func play(
        _ collection: PlayableContent,
        items: [PlayableContent]? = nil,
        mode: PlayMode,
        selectedGroupService: SelectedGroupService
    ) {
        Task { @MainActor in
            HapticManager.shared.fireHaptic(.buttonPress)
            let contents: [PlayableContent]
            if let items {
                contents = items
            } else {
                // Read before the destination is picked: this device needs
                // the items to start.
                contents = await PlexBrowseService.shared.allCollectionItems(of: collection)
            }
            guard !contents.isEmpty else {
                AlertService.shared.showAlert(with: "Couldn't load \(collection.title) from Plex", imageName: "exclamationmark.triangle.fill")
                return
            }

            let queue: (GroupRoom, QueuePosition) async throws -> Void = { group, position in
                await queueOnSpeaker(contents, of: collection, on: group, position: position, mode: mode)
            }
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(contents, position: .replace, shuffle: mode.isShuffleEnabled, from: collection, queue: queue)
                return
            }
            await queueOnSpeaker(contents, of: collection, on: group, position: .replace, mode: mode)
        }
    }

    private static func queueOnSpeaker(
        _ contents: [PlayableContent],
        of collection: PlayableContent,
        on group: GroupRoom,
        position: QueuePosition,
        mode: PlayMode
    ) async {
        let sonosService = SonosService.shared
        let alertService = AlertService.shared
        let noun = itemNoun(for: contents)
        // Queueing a collection takes a beat per item, so the banner counts
        // them in rather than sitting silent until the end.
        alertService.showLoadingProgress(with: collection, subtitle: "Adding \(noun) 1 of \(contents.count)", fraction: 0)
        let progress: @MainActor (Int, Int) -> Void = { added, total in
            let next = min(added + 1, total)
            alertService.showLoadingProgress(
                with: collection,
                subtitle: "Adding \(noun) \(next) of \(total)",
                fraction: Double(added) / Double(max(total, 1))
            )
        }

        await sonosService.setPlayMode(group.ip, mode: mode)
        group.playMode = mode
        Router.main.show(destination: .player(groupID: group.coordinatorID))

        do {
            switch position {
            case .now:
                try await sonosService.playNext(contents, on: group, progress: progress)
            case .replace:
                // startIndex 0: playback begins as soon as the first item
                // lands instead of waiting for the whole collection.
                try await sonosService.queue(contents: contents, group: group, position: .replace, startIndex: 0, progress: progress)
            case .next, .end, .front:
                try await sonosService.queue(contents: contents, group: group, position: position, progress: progress)
            }
            let done: LocalizedStringKey = [.now, .replace].contains(position)
                ? "Playing \(contents.count) \(noun)s"
                : "Added \(contents.count) \(noun)s"
            alertService.showAlertContent(with: collection, subtitle: contents.count == 1 ? "Playing" : done, symbolName: "checkmark")
        } catch {
            alertService.showAlert(with: "Failed to queue \(collection.title), ensure Plex is authorized in Sonos", imageName: "exclamationmark.triangle.fill")
        }
    }

    /// What a collection holds, for the banner: "album", "artist" or "song".
    private static func itemNoun(for contents: [PlayableContent]) -> String {
        switch contents.first?.content.type {
        case .artist, .libraryArtist: "artist"
        case .track, .libraryTrack: "song"
        default: "album"
        }
    }
}
