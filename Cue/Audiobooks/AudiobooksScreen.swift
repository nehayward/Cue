import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Audiobooks tab: Continue Listening, the books not yet finished with
/// the one listened to last on top, each one tap from where it was left;
/// the books on this device; a section for each server, its newest books
/// with the way to every one; and what was finished lately.
///
/// What's been listened to comes from two places: this device's history
/// (`PlayHistoryService`, which `AudiobookPlayer` writes the book to when
/// it plays) and Audiobookshelf's own list of books in progress, so a book
/// started in another app is here too. Both are ordered by when the book's
/// place last moved (`AudiobookProgressStore`), newest first.
struct AudiobooksScreen: View {
    @Environment(CoreFeatures.self) private var coreFeatures
    @AppStorage(AppStorageKeys.hasPlexAudiobooks) private var hasPlexBooks = false

    /// This tab's own stack, never a shared router: two stacks bound to one
    /// path push each other.
    @State private var router = Router()
    @State private var store = AudiobookProgressStore.shared
    @State private var shelf = AudiobookshelfBrowseService.shared
    @State private var player = AudiobookPlayer.shared
    /// Plex's newest books, for its section's row.
    @State private var plexPreview: [PlayableContent] = []
    @State private var isLoadingPlex = false

    private var showsPlex: Bool { coreFeatures.isEnabled(.plex) && hasPlexBooks }
    private var showsAudiobookshelf: Bool { coreFeatures.isEnabled(.audiobookshelf) && shelf.isAuthenticated }

    var body: some View {
        // Offline, only what's whole on this device plays.
        let isOffline = OfflineMode.shared.isActive
        let listened = isOffline ? listenedBooks.filter(AudiobookDownloads.isDownloaded) : listenedBooks
        let continuing = continuing(listened, isOffline: isOffline)
        let finished = listened.filter { store.progress(for: $0)?.isFinished == true }
        let downloaded = AudiobookDownloads.downloadedBooks(completeOnly: isOffline)

        NavigationStack(path: $router.path) {
            List {
                AudiobookContinueCard(books: continuing)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)

                // On this device or on their way: what plays with no network.
                if !downloaded.isEmpty {
                    Section {
                        AudiobookSectionTitle(title: "Downloads", destination: .bookDownloads)
                        AudiobookCoverRow(books: downloaded)
                            .listRowInsets(EdgeInsets())
                    }
                    .fontDesign(.rounded)
                    .listRowSeparator(.hidden)
                }

                if !isOffline {
                    libraries
                        .fontDesign(.rounded)
                }

                if !finished.isEmpty {
                    Section {
                        AudiobookSectionTitle(title: "Finished")
                        ForEach(finished.prefix(Self.recentCount)) { book in
                            AudiobookRow(book: book)
                        }
                    }
                    .fontDesign(.rounded)
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            // Rounded is set on each part rather than here: the outermost
            // `.fontDesign` wins, and the book's title is New York.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .navigationTitle("Audiobooks")
            .task {
                await load()
            }
            .refreshable {
                await load(refreshing: true)
            }
            .miniPlayerOnScrollHandler()
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    private static let recentCount = 10

    /// Every book not finished, started or only tried, as Audible has it.
    /// The book loaded to play leads even before a reading has come in
    /// (offline, only one downloaded: anything else won't play).
    private func continuing(_ listened: [PlayableContent], isOffline: Bool) -> [PlayableContent] {
        var books = listened.filter { store.progress(for: $0)?.isFinished != true }
        if let loaded = player.current?.book, !isOffline || AudiobookDownloads.isDownloaded(loaded),
           store.progress(for: loaded)?.isFinished != true, !books.contains(where: { $0.isSameBook(as: loaded) }) {
            books.insert(loaded, at: 0)
        }
        return books
    }

    /// Every book listened to, once each, newest first.
    private var listenedBooks: [PlayableContent] {
        AudiobookLibrary.listenedBooks(plex: coreFeatures.isEnabled(.plex), audiobookshelf: showsAudiobookshelf)
    }

    // MARK: - Libraries

    /// A section for each server: its newest books as a row of covers, and
    /// the title opening every book it has.
    @ViewBuilder
    private var libraries: some View {
        if showsPlex {
            Section {
                AudiobookSectionTitle(title: "Plex", destination: plexBooks)
                if !plexPreview.isEmpty {
                    AudiobookCoverRow(books: plexPreview)
                        .listRowInsets(EdgeInsets())
                } else if isLoadingPlex {
                    // Plex's books are read whole, which takes a moment:
                    // their room is kept so the sections below don't move.
                    AudiobookCoverRowPlaceholder()
                        .listRowInsets(EdgeInsets())
                }
            }
            .listRowSeparator(.hidden)
        }
        if showsAudiobookshelf, let library = shelf.selectedLibrary {
            Section {
                AudiobookSectionTitle(
                    title: LocalizedStringKey(shelf.libraries.count > 1 ? "Audiobookshelf · \(library.name)" : "Audiobookshelf"),
                    destination: audiobookshelfBooks(in: library)
                )
                if !shelf.recentlyAdded.isEmpty {
                    AudiobookCoverRow(books: shelf.recentlyAdded)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    /// Every Plex book, by title.
    private var plexBooks: RouterDestination {
        .playableList(
            title: "Plex",
            showSectionIndex: false,
            allowsGrid: true,
            // A pull has Plex scan for books added on the server.
            refreshAction: { await AudiobookLibrary.scanPlexBooks() },
            loadingStatus: { PlexBookScan.shared.status },
            action: { offset in
                // Read whole: the shelf merges several sources.
                guard offset == 0 else { return [] }
                return await AudiobookLibrary.plexShelf()
            }
        )
    }

    /// Every book in the Audiobookshelf library, in the order picked.
    private func audiobookshelfBooks(in library: AudiobookshelfLibrary) -> RouterDestination {
        .playableList(
            title: library.name,
            showSectionIndex: false,
            allowsGrid: true,
            sortOptions: shelf.bookSortOptions,
            sortKey: "audiobookshelf.books",
            searchAction: { query, offset in
                // The server answers a search in one go.
                guard offset == 0 else { return [] }
                return await shelf.search(query)
            }
        )
    }

    // MARK: - Loading

    private func load(refreshing: Bool = false) async {
        if showsAudiobookshelf {
            if refreshing || shelf.libraries.isEmpty {
                await shelf.refresh()
            }
        }
        if coreFeatures.isEnabled(.plex) {
            await AudiobookLibrary.checkPlexBooks()
            // Once a launch, and on a pull: Plex's books are read whole.
            if hasPlexBooks, refreshing || plexPreview.isEmpty {
                isLoadingPlex = true
                if let newest = await AudiobookLibrary.plexNewestBooks() {
                    plexPreview = newest
                }
                isLoadingPlex = false
            }
        }
    }
}

// MARK: - Continue Listening

/// The tab's lead, as Audible has it: one card of the books not finished,
/// the one listened to last on top, each with its own Play. Past the first
/// few, the title opens them all.
struct AudiobookContinueCard: View {
    let books: [PlayableContent]

    @Environment(Router.self) private var router
    @State private var store = AudiobookProgressStore.shared

    private static let shownCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.navigate(to: allBooks)
            } label: {
                HStack {
                    Text("Continue Listening")
                    Spacer()
                    if books.count > Self.shownCount {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title3.bold())
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(books.count <= Self.shownCount)
            .accessibilityAddTraits(.isHeader)
            .fontDesign(.rounded)
            .padding(.bottom, 6)

            if books.isEmpty {
                Text("The books you're listening to wait here, ready to pick up where you left them.")
                    .font(.callout)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            // Rounded is set on each part rather than here: the outermost
            // `.fontDesign` wins, and the book's title is New York.
            ForEach(books.prefix(Self.shownCount)) { book in
                AudiobookContinueRow(book: book)
                    .padding(.vertical, 8)
            }
        }
        // A book played moves to the top: the rows slide into their new
        // order rather than jump.
        .animation(.smooth, value: books.prefix(Self.shownCount).map(\.id))
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 24))
    }

    /// Every book not finished, as a list of its own.
    private var allBooks: RouterDestination {
        let books = books
        let store = store
        return .playableList(title: "Continue Listening", showSectionIndex: false) { offset in
            guard offset == 0 else { return [] }
            return books.map { $0.withAudiobookProgress(store.progress(for: $0)) }
        }
    }
}

/// A book in Continue Listening: its cover, title and author, how far in
/// (or how long, before it's started), and a round Play — Pause while it
/// plays. The rest of the row opens the book's page; a long press, its menu.
struct AudiobookContinueRow: View {
    let book: PlayableContent

    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared
    /// This row's Play is starting the book, read from its server first.
    @State private var isStarting = false

    private var route: PlaybackRoute { .shared }

    /// The book is loaded and the player has it.
    private var isLoaded: Bool {
        player.current?.book.isSameBook(as: book) == true && player.isPlayingBook(on: route.presented)
    }

    var body: some View {
        let progress = store.progress(for: book)
        let isPlaying = isLoaded && route.presented.isPlaying
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.navigate(to: .audiobookDetail(content: book))
            } label: {
                HStack(spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 3) {
                        // New York, a book's own face, for its title; the
                        // lines under it are rounded, set on themselves.
                        Text(book.title)
                            .font(.headline)
                            .fontDesign(.serif)
                            .lineLimit(2)
                        if !book.subtitle.isEmpty {
                            Text(book.subtitle)
                                .font(.subheadline)
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let progress {
                            progressLine(progress)
                                .fontDesign(.rounded)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(book.title)")

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task {
                    if isLoaded {
                        await route.presented.togglePlayback()
                    } else {
                        isStarting = true
                        await player.play(book)
                        isStarting = false
                    }
                }
            } label: {
                VStack {
                    if isStarting {
                        ProgressView()
                    } else {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .contentTransition(GroupMediaControlsView.playPauseTransition)
                    }
                }
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(isStarting || player.isLoading)
            .accessibilityLabel(isPlaying ? "Pause" : progress?.isStarted == true ? "Resume" : "Play")
        }
        // The book's menu (from the start, download or remove) is a long
        // press away, as on its other rows.
        .contextMenu {
            PlayableMenuView(item: book)
        }
    }

    private var cover: some View {
        ContentArtworkView(content: book, showMusicSource: false, preferredSize: 200, cornerRadius: 6)
            .frame(width: 72, height: 72)
            .overlay(alignment: .bottomTrailing) {
                // On this device: it plays with no network.
                if DownloadManager.shared.containerPresence(for: book) == .downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .font(.footnote)
                        .padding(4)
                        .accessibilityLabel("Downloaded")
                }
            }
    }

    /// How far in, as a bar and what's left ("15h 25m left"); the book's
    /// length before it's started.
    @ViewBuilder
    private func progressLine(_ progress: AudiobookProgress) -> some View {
        if progress.isStarted, let fraction = progress.fraction {
            HStack(spacing: 10) {
                // The bar gives way to the time, which keeps to one line.
                AudiobookProgressBar(fraction: fraction)
                    .frame(minWidth: 24, maxWidth: 72)
                if let remaining = AudiobookFormat.remaining(progress) {
                    Text(remaining)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } else if progress.duration > 0 {
            Text(AudiobookFormat.duration(progress.duration))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - A row of covers

/// Books as a sideways row of covers with their titles, each opening its
/// page.
struct AudiobookCoverRow: View {
    let books: [PlayableContent]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(books) { book in
                    NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
                        VStack(alignment: .leading, spacing: 4) {
                            ContentArtworkView(content: book, showMusicSource: false, preferredSize: 300, cornerRadius: 6)
                                .frame(width: Self.coverSize, height: Self.coverSize)
                            Text(book.title)
                                .font(.footnote)
                                .lineLimit(1)
                            Text(book.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: Self.coverSize)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AudiobookMenuItems(book: book)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    static let coverSize: CGFloat = 120
}

/// A row of covers still on its way: grey squares the size of the covers,
/// so the row takes its room before its books arrive.
struct AudiobookCoverRowPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.fill.tertiary)
                        .frame(width: AudiobookCoverRow.coverSize, height: AudiobookCoverRow.coverSize)
                    Text(verbatim: "Book title")
                        .font(.footnote)
                    Text(verbatim: "Author")
                        .font(.caption)
                }
                .frame(width: AudiobookCoverRow.coverSize, alignment: .leading)
            }
        }
        .redacted(reason: .placeholder)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

extension PlayableContent {
    /// The same book, wherever the copy came from: by its server and id,
    /// as `AudiobookProgressStore` keys it.
    func isSameBook(as other: PlayableContent?) -> Bool {
        guard let other else { return false }
        return content.service == other.content.service && content.id == other.content.id
    }
}

/// A section's title, as its first row rather than its header: a plain
/// list pins a header to the top while its section scrolls under it, and
/// these scroll away with their section. Drawn as the list's prominent
/// header was; with a `destination`, a chevron says the title opens it.
private struct AudiobookSectionTitle: View {
    let title: LocalizedStringKey
    var destination: RouterDestination?

    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading) {
            if let destination {
                // A button, not a link: a link in a plain list draws its
                // own disclosure arrow, small and grey.
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.navigate(to: destination)
                } label: {
                    HStack {
                        Text(title)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
            }
        }
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
