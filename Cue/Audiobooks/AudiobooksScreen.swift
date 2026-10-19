import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Audiobooks tab: the book listened to last, large, one tap from where
/// it was left; what else is partway through; what was played lately; and
/// every book on Plex and Audiobookshelf.
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

    private var showsPlex: Bool { coreFeatures.isEnabled(.plex) && hasPlexBooks }
    private var showsAudiobookshelf: Bool { coreFeatures.isEnabled(.audiobookshelf) && shelf.isAuthenticated }

    var body: some View {
        let listened = listenedBooks
        let inProgress = listened.filter { store.progress(for: $0)?.isStarted == true }
        // The book loaded to play leads even before a reading has come in.
        let hero = inProgress.first ?? player.current?.book
        let others = inProgress.filter { !$0.isSameBook(as: hero) }
        let recent = listened.filter { book in
            !book.isSameBook(as: hero) && !inProgress.contains { $0.isSameBook(as: book) }
        }

        NavigationStack(path: $router.path) {
            List {
                if let hero {
                    AudiobookResumeCard(book: hero)
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                } else {
                    Text("The book you're listening to waits here, ready to pick up where you left it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                }

                if !others.isEmpty {
                    Section {
                        ForEach(others) { book in
                            AudiobookRow(book: book)
                        }
                    } header: {
                        Text("Continue Listening")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)
                }

                if showsAudiobookshelf, !shelf.recentlyAdded.isEmpty {
                    Section {
                        AudiobookCoverRow(books: shelf.recentlyAdded)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text("Recently Added")
                    }
                    .listRowSeparator(.hidden)
                }

                if !recent.isEmpty {
                    Section {
                        ForEach(recent.prefix(Self.recentCount)) { book in
                            AudiobookRow(book: book)
                        }
                    } header: {
                        Text("Recently Played")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)
                }

                libraries
            }
            .listStyle(.plain)
            .headerProminence(.increased)
            .fontDesign(.rounded)
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

    /// Every book listened to, once each, newest first.
    private var listenedBooks: [PlayableContent] {
        AudiobookLibrary.listenedBooks(plex: coreFeatures.isEnabled(.plex), audiobookshelf: showsAudiobookshelf)
    }

    // MARK: - Libraries

    @ViewBuilder
    private var libraries: some View {
        if showsPlex || showsAudiobookshelf {
            Section {
                if showsPlex {
                    NavigationLink(value: RouterDestination.playableList(
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
                    )) {
                        Label {
                            Text("Plex")
                        } icon: {
                            MediaSearchService.plex.tabImage
                        }
                    }
                }
                if showsAudiobookshelf, let library = shelf.selectedLibrary {
                    NavigationLink(value: RouterDestination.playableList(
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
                    )) {
                        Label {
                            Text(shelf.libraries.count > 1 ? "Audiobookshelf · \(library.name)" : "Audiobookshelf")
                        } icon: {
                            MediaSearchService.audiobookshelf.tabImage
                        }
                    }
                }
            } header: {
                Text("All Books")
            }
            .listRowInsets(.default)
            .listRowSeparator(.hidden)
        }
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
        }
    }
}

// MARK: - The book listened to last

/// The tab's lead: the book's cover, how far in, the chapter when it's the
/// one loaded, and Resume — or Pause while it plays. The cover opens the
/// book's page.
struct AudiobookResumeCard: View {
    let book: PlayableContent

    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared

    private var route: PlaybackRoute { .shared }

    /// The book is loaded and the player has it.
    private var isLoaded: Bool {
        player.current?.book.isSameBook(as: book) == true && player.isPlayingBook(on: route.presented)
    }

    private var isPlaying: Bool {
        isLoaded && route.presented.isPlaying
    }

    var body: some View {
        let progress = store.progress(for: book)
        HStack(alignment: .top, spacing: 16) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.navigate(to: .audiobookDetail(content: book))
            } label: {
                ContentArtworkView(content: book, showMusicSource: false, preferredSize: 300, cornerRadius: 8)
                    .frame(width: 136, height: 136)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(book.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                if !book.subtitle.isEmpty {
                    Text(book.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isLoaded, let chapter = player.currentChapter, (player.current?.chapters.count ?? 0) > 1 {
                    Text(chapter.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let progress, let fraction = progress.fraction {
                    AudiobookProgressBar(fraction: fraction)
                    if let remaining = AudiobookFormat.remaining(progress) {
                        Text(remaining)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task {
                        if isLoaded {
                            await route.presented.togglePlayback()
                        } else {
                            await player.play(book)
                        }
                    }
                } label: {
                    Group {
                        if player.isLoading {
                            ProgressView()
                        } else {
                            Text("\(Image(systemName: isPlaying ? "pause.fill" : "play.fill")) \(buttonTitle(progress))")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .glassButton()
                .foregroundStyle(.primary)
                .bold()
                .disabled(player.isLoading)
                .padding(.top, 4)
            }
            .frame(minHeight: 136)
        }
        .padding(.vertical, 8)
    }

    private func buttonTitle(_ progress: AudiobookProgress?) -> String {
        if isPlaying { return "Pause" }
        return progress?.isStarted == true ? "Resume" : "Play"
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
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private static let coverSize: CGFloat = 120
}

extension PlayableContent {
    /// The same book, wherever the copy came from: by its server and id,
    /// as `AudiobookProgressStore` keys it.
    func isSameBook(as other: PlayableContent?) -> Bool {
        guard let other else { return false }
        return content.service == other.content.service && content.id == other.content.id
    }
}
