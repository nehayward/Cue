import Defaults
import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// Someone who writes books: their name, and their Plex artist (a book's
/// album artist, whose picture is theirs) when there is one.
struct AudiobookAuthor: Hashable {
    let name: String
    var plexArtistID: String?

    /// The author of what an artist page was opened for, when it's a book
    /// or one of a book's files (the player's artist line on a book): their
    /// page is their books, not an artist's popular songs, which for an
    /// author are a book's files. Nil for anything else.
    @MainActor
    init?(for content: PlayableContent) {
        guard let book = AudiobookPlayer.shared.book(containing: content) else { return nil }
        let name = (book.metadata?.artist ?? book.subtitle).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        self.name = name
        plexArtistID = book.content.service == .plex ? book.metadata?.artistID : nil
    }

    /// Whether `book` is theirs: their Plex artist's, or by their name,
    /// any one of the authors of a book with several.
    func wrote(_ book: PlayableContent) -> Bool {
        if let plexArtistID, book.content.service == .plex, book.metadata?.artistID == plexArtistID {
            return true
        }
        return (book.metadata?.artist ?? book.subtitle)
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}

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
    @State private var books: [PlayableContent] = []
    /// Their picture: their Plex artist's, else Audiobookshelf's, else
    /// Audible's.
    @State private var portrait: URL?
    /// Their biography: Audiobookshelf's, else Audible's.
    @State private var about: String?
    /// The genres Audible files them under.
    @State private var genres: [String] = []
    @State private var isLoading = true

    init(author: AudiobookAuthor) {
        self.author = author
        // What Audible said last time, from the first frame: the page opens
        // whole rather than filling in.
        let kept = AudiobookAuthorInfo.cached(named: author.name)
        _portrait = State(initialValue: kept?.imageURL)
        _about = State(initialValue: Self.about(kept, server: nil))
        _genres = State(initialValue: Self.genres(kept))
    }

    var body: some View {
        let partway = books.filter { book in
            store.progress(for: book).map { $0.isStarted && !$0.isFinished } ?? false
        }
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
            Group {
                if let portrait {
                    LazyImage(url: portrait) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            monogram
                        }
                    }
                } else {
                    monogram
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(.circle)
            .accessibilityHidden(true)

            // New York, as their books' titles are.
            Text(author.name)
                .font(.title.bold())
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Group {
                if !books.isEmpty {
                    Text(countLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !genres.isEmpty {
                    Text(genres.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .fontDesign(.rounded)
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

    /// Their books from each server and what's known of them, all at once,
    /// shown in one change: the page lays out once rather than shifting
    /// as each part lands. Audible is waited for only so long; with it slow
    /// or out of reach the books don't wait, and its answer fills in when
    /// it comes. Offline, the books downloaded.
    private func load() async {
        if OfflineMode.shared.isActive {
            books = Self.ordered(AudiobookDownloads.downloadedBooks().filter(author.wrote))
            isLoading = false
            return
        }
        let lookup = Task { await AudiobookAuthorInfo.author(named: author.name) }
        async let plex = plexBooks()
        async let shelf = audiobookshelfBooks()
        async let picture = plexPortrait()
        let (plexFound, shelfFound, plexImage) = await (plex, shelf, picture)
        let image = plexImage ?? shelfFound.image
        let audible = await Self.answer(of: lookup, within: .seconds(3))
        books = Self.ordered(plexFound + shelfFound.books)
        isLoading = false
        show(audible ?? AudiobookAuthorInfo.cached(named: author.name), image: image, about: shelfFound.about)
        if audible == nil {
            show(await lookup.value, image: image, about: shelfFound.about)
        }
    }

    /// The servers' picture and biography where they have them, Audible's
    /// for the rest.
    private func show(_ audible: AudnexusAuthor?, image: URL?, about server: String?) {
        portrait = image ?? audible?.imageURL
        about = Self.about(audible, server: server)
        genres = Self.genres(audible)
    }

    private static func about(_ audible: AudnexusAuthor?, server: String?) -> String? {
        server ?? audible?.description.map(AudiobookText.plain).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Two, which keep to a line.
    private static func genres(_ audible: AudnexusAuthor?) -> [String] {
        (audible?.genres ?? []).filter { $0.type == "genre" }.prefix(2).map(\.name)
    }

    /// `lookup`'s answer, or nil once `limit` has passed; the lookup goes
    /// on either way.
    private static func answer(of lookup: Task<AudnexusAuthor?, Never>, within limit: Duration) async -> AudnexusAuthor?? {
        await withCheckedContinuation { continuation in
            let first = FirstAnswer(continuation)
            Task { @MainActor in first.give(.some(await lookup.value)) }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                first.give(nil)
            }
        }
    }

    private func plexBooks() async -> [PlayableContent] {
        guard coreFeatures.isEnabled(.plex), hasPlexBooks else { return [] }
        return (await AudiobookLibrary.plexBooks() ?? []).filter(author.wrote)
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

/// What Audible knows of each author (`AudnexusAuthor`: picture, biography,
/// genres), kept in Caches by name, so an author's page opened again
/// doesn't ask. Someone Audible doesn't know is asked again after a day,
/// someone it does after a month; with Audnexus out of reach, what was
/// kept stands.
@MainActor
enum AudiobookAuthorInfo {
    private struct Entry: Codable {
        var author: AudnexusAuthor?
        var askedAt: Date
    }

    private static var entries: [String: Entry] = load()
    private static let knownLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let unknownLifetime: TimeInterval = 24 * 60 * 60
    private static let io = DispatchQueue(label: "dance.cue.audiobookAuthors", qos: .utility)

    /// Audible's record of `name`; nil when it has none or couldn't be
    /// asked.
    static func author(named name: String) async -> AudnexusAuthor? {
        let key = name.lowercased()
        if let entry = entries[key],
           Date.now.timeIntervalSince(entry.askedAt) < (entry.author == nil ? unknownLifetime : knownLifetime) {
            return entry.author
        }
        switch await AudnexusAPI.author(named: name) {
        case let .found(author):
            remember(author, for: key)
            return author
        case .notFound:
            remember(nil, for: key)
            return nil
        case .unreachable:
            return entries[key]?.author
        }
    }

    /// What was kept for `name`, without asking: offline.
    static func cached(named name: String) -> AudnexusAuthor? {
        entries[name.lowercased()]?.author
    }

    private static func remember(_ author: AudnexusAuthor?, for key: String) {
        entries[key] = Entry(author: author, askedAt: .now)
        guard let url = fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        io.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "AudiobookAuthors.json")
    }

    private static func load() -> [String: Entry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }
}

/// Resumes its continuation with the first answer it's given.
@MainActor
private final class FirstAnswer<Value> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func give(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
