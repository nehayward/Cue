import Defaults
import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// An author's page, in place of an artist's for someone who writes books:
/// their picture, name and biography, the genres they write in, the books
/// of theirs partway through, each with its Play, and every book of theirs
/// on Plex and Audiobookshelf as covers, oldest first, each with how far in
/// it is. Offline, the ones downloaded. The picture and biography are the
/// servers' where they keep them, else Audible's (`AudiobookAuthorInfo`).
struct AudiobookAuthorView: View {
    let author: AudiobookAuthor

    @Environment(CoreFeatures.self) private var coreFeatures
    @AppStorage(AppStorageKeys.hasPlexAudiobooks) private var hasPlexBooks = false
    @State private var store = AudiobookProgressStore.shared
    @State private var audibleInfo = AudiobookAuthorInfo.shared
    @State private var books: [PlayableContent] = []
    /// Their picture as their servers keep it: their Plex artist's, else
    /// Audiobookshelf's.
    @State private var serverPortrait: URL?
    /// Their biography as Audiobookshelf keeps it.
    @State private var serverAbout: String?
    @State private var isLoading = true

    /// What Audible knows of them, as last kept: there from the first
    /// frame, so the page opens whole, and redrawn when an answer lands.
    private var audible: AudnexusAuthor? {
        audibleInfo.author(named: author.name)
    }

    /// Their picture: their servers', else Audible's.
    private var portrait: URL? {
        serverPortrait ?? audible?.imageURL
    }

    /// Their biography: Audiobookshelf's, else Audible's.
    private var about: String? {
        serverAbout ?? audible?.description.map(AudiobookText.plain).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The genres Audible files them under: two, which keep to a line.
    private var genres: [String] {
        (audible?.genres ?? []).filter { $0.type == "genre" }.prefix(2).map(\.name)
    }

    /// Their books partway through.
    private var partway: [PlayableContent] {
        books.filter { book in
            store.progress(for: book).map { $0.isStarted && !$0.isFinished } ?? false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                // New York, as a book's summary is.
                if let about {
                    AudiobookSummary(text: about)
                }

                if !partway.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("Continue Listening")
                        ForEach(partway) { book in
                            AudiobookContinueRow(book: book)
                                .padding(.vertical, 6)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Books")
                    if isLoading, books.isEmpty {
                        grid { placeholderTiles }
                    } else if books.isEmpty {
                        Text("No books by \(author.name) on your servers.")
                            .font(.callout)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    } else {
                        let shared = sharedTitles
                        grid {
                            ForEach(books) { book in
                                AudiobookAuthorBookTile(book: book, showsServer: shared.contains(Self.titleKey(book)))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle(author.name)
        .navigationBarTitleDisplayMode(.inline)
        // No pull to refresh: it's read afresh each time it opens, and in a
        // sheet (from the player) the pull is the sheet's, to dismiss it.
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            // Their initials while there's no picture, or none at all.
            LazyImage(url: portrait) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    monogram
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(.circle)
            .accessibilityHidden(true)

            // New York, as their books' titles are; the lines under it set
            // rounded on themselves.
            Text(author.name)
                .font(.title.bold())
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            if !books.isEmpty {
                Text(countLine)
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
            if !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.footnote)
                    .fontDesign(.rounded)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    /// Their initials, until (or unless) a picture comes.
    private var monogram: some View {
        Text(initials)
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.fill.tertiary)
    }

    private var initials: String {
        author.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }

    /// "4 books · 1 finished".
    private var countLine: String {
        let finished = books.filter { store.progress(for: $0)?.isFinished == true }.count
        let count = books.count == 1 ? "1 book" : "\(books.count) books"
        return finished > 0 ? "\(count) · \(finished) finished" : count
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.bold())
            .fontDesign(.rounded)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Books

    private func grid(@ViewBuilder _ content: () -> some View) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
            content()
        }
    }

    private var placeholderTiles: some View {
        ForEach(0..<4, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.fill.tertiary)
                    .aspectRatio(1, contentMode: .fit)
                Text(verbatim: "Book title")
                    .font(.subheadline)
                Text(verbatim: "2021")
                    .font(.caption)
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
    }

    /// Titles on more than one server: those tiles say which one.
    private var sharedTitles: Set<String> {
        var seen = Set<String>()
        var shared = Set<String>()
        for book in books where !seen.insert(Self.titleKey(book)).inserted {
            shared.insert(Self.titleKey(book))
        }
        return shared
    }

    private static func titleKey(_ book: PlayableContent) -> String {
        book.title.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Loading

    /// Their books from each server and what the servers keep of them, all
    /// at once, shown in one change: the page lays out once rather than
    /// shifting as each part lands. Audible's record isn't waited for: it
    /// lands in `AudiobookAuthorInfo`, which the page reads, so one kept
    /// from before is there from the first frame and a new one fills in
    /// when it comes. Offline, the books downloaded.
    private func load() async {
        if OfflineMode.shared.isActive {
            books = Self.ordered(AudiobookDownloads.downloadedBooks().filter(author.wrote))
            isLoading = false
            return
        }
        audibleInfo.refresh(named: author.name)
        async let plex = plexBooks()
        async let shelf = audiobookshelfBooks()
        async let picture = plexPortrait()
        let (plexFound, shelfFound, plexImage) = await (plex, shelf, picture)
        books = Self.ordered(plexFound + shelfFound.books)
        serverPortrait = plexImage ?? shelfFound.image
        serverAbout = shelfFound.about
        isLoading = false
    }

    /// Their artist's books in one request; for an author known only by
    /// name, every book read and theirs kept.
    private func plexBooks() async -> [PlayableContent] {
        guard coreFeatures.isEnabled(.plex), hasPlexBooks else { return [] }
        guard let artistKey = author.plexArtistID else {
            return (await AudiobookLibrary.plexBooks() ?? []).filter(author.wrote)
        }
        return await AudiobookLibrary.plexBooks(byArtist: artistKey, isTheirs: author.wrote)
    }

    /// Their author entry's books and picture; for a name it lists another
    /// way ("Weir, Andy"), the books its search finds that are theirs.
    private func audiobookshelfBooks() async -> (books: [PlayableContent], image: URL?, about: String?) {
        let shelf = AudiobookshelfBrowseService.shared
        guard coreFeatures.isEnabled(.audiobookshelf), shelf.isAuthenticated else { return ([], nil, nil) }
        if let found = await shelf.author(named: author.name) {
            return found
        }
        return (await shelf.search(author.name).filter(author.wrote), nil, nil)
    }

    private func plexPortrait() async -> URL? {
        guard let id = author.plexArtistID, coreFeatures.isEnabled(.plex) else { return nil }
        return await MusicSearchService.shared.lookupPlexArtist(id: id)?.artwork
    }

    /// The order they came out, then by title; a book with no year after
    /// those with one.
    private static func ordered(_ books: [PlayableContent]) -> [PlayableContent] {
        books.sorted { lhs, rhs in
            switch (lhs.metadata?.albumYear, rhs.metadata?.albumYear) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

/// A book on its author's page: its cover with how far in it is, its title
/// in New York, and its year, or what's left of it. `showsServer` names its
/// server, for a title on both.
private struct AudiobookAuthorBookTile: View {
    let book: PlayableContent
    let showsServer: Bool

    @State private var store = AudiobookProgressStore.shared

    var body: some View {
        let progress = store.progress(for: book)
        NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ContentArtworkView(content: book, showMusicSource: false, preferredSize: 400, cornerRadius: 8)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .bottom) {
                        if let progress, progress.isStarted, !progress.isFinished, let fraction = progress.fraction {
                            AudiobookProgressBar(fraction: fraction, tint: .white, isRounded: false)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if progress?.isFinished == true {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .font(.title3)
                                .padding(6)
                                .accessibilityLabel("Finished")
                        }
                    }

                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.serif)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let detail = detail(progress) {
                    Text(detail)
                        .font(.caption)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            AudiobookMenuItems(book: book)
        }
    }

    /// What's left of a book partway through, else its year; the server
    /// in front for a title on both.
    private func detail(_ progress: AudiobookProgress?) -> String? {
        var parts: [String] = []
        if showsServer {
            parts.append(book.content.service.title)
        }
        if let progress, progress.isStarted, !progress.isFinished, let remaining = AudiobookFormat.remaining(progress) {
            parts.append(remaining)
        } else if let year = book.metadata?.albumYear {
            parts.append(year.formatted(.dateTime.year()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
