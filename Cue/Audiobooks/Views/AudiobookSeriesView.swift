import MusicSearchKit
import SonosKit
import SwiftUI

/// A series' page, after Apple Books': its covers stacked, its name, who
/// wrote and reads it, a Play for the book to listen to next, and its books
/// as a grid in their order. A series read more than once (Harry Potter by
/// Jim Dale, Stephen Fry and a full cast) has a pill for each reading, and
/// shows one at a time (`narrations(of:)`).
struct AudiobookSeriesView: View {
    let name: String
    let books: [PlayableContent]

    @State private var details = AudiobookDetails.shared
    /// The readings, worked out when what's known of the books changes,
    /// not on every redraw: a pill tap redraws the page from these.
    @State private var narrations: [Narration] = []
    /// The reading picked, by its name; nil for the first.
    @State private var chosen: String?

    /// One reading of the series, its books in their order.
    struct Narration: Identifiable, Equatable {
        /// A book, and what it is in the series ("Book 2").
        struct Entry: Identifiable, Equatable {
            let book: PlayableContent
            let label: String
            var id: String { book.id }
        }

        /// Who reads it, "Full Cast", or `unknownReading` for books whose
        /// reader isn't known.
        let id: String
        let entries: [Entry]

        var books: [PlayableContent] { entries.map(\.book) }
    }

    /// The reading of books no source could name a reader for: a copy
    /// Audible doesn't sell (none as long as it), whose files Plex streams
    /// without their tags.
    static let unknownReading = "Unknown Narrator"

    /// `books` by who reads them, each in the series' order; the reading
    /// listened to last first, then the one with the most books, and the
    /// books no one could name a reader for last.
    ///
    /// A book whose reader isn't known joins the one reading that lacks its
    /// place in the series, when only one does: Stephen Fry's first six
    /// Harry Potters are editions Audible's public catalog no longer lists,
    /// but his seventh matched, and the full cast already has all seven.
    @MainActor
    static func narrations(of books: [PlayableContent]) -> [Narration] {
        let details = AudiobookDetails.shared
        let store = AudiobookProgressStore.shared
        var grouped = Dictionary(grouping: books) { book in
            AudiobookDetails.narration(details.details(for: book)?.narrators ?? []) ?? Self.unknownReading
        }
        if let unknown = grouped[unknownReading] {
            var left: [PlayableContent] = []
            for book in unknown {
                guard let place = details.details(for: book)?.place else {
                    left.append(book)
                    continue
                }
                let lacking = grouped.keys.filter { label in
                    label != unknownReading && !(grouped[label] ?? []).contains { details.details(for: $0)?.place == place }
                }
                if lacking.count == 1, let label = lacking.first {
                    grouped[label, default: []].append(book)
                } else {
                    left.append(book)
                }
            }
            grouped[unknownReading] = left.isEmpty ? nil : left
        }
        func lastListened(_ books: [PlayableContent]) -> Date? {
            books.compactMap { store.progress(for: $0)?.updatedAt }.max()
        }
        return grouped
            .map { label, books in
                let ordered = books.sorted(by: details.inSeriesOrder)
                // Its place in the series, else in this reading.
                let entries = ordered.enumerated().map { index, book in
                    Narration.Entry(book: book, label: "Book \(details.details(for: book)?.sequence ?? "\(index + 1)")")
                }
                return Narration(id: label, entries: entries)
            }
            .sorted {
                if ($0.id == unknownReading) != ($1.id == unknownReading) { return $1.id == unknownReading }
                switch (lastListened($0.books), lastListened($1.books)) {
                case let (a?, b?) where a != b: return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                default: return $0.books.count != $1.books.count ? $0.books.count > $1.books.count : $0.id < $1.id
                }
            }
    }

    var body: some View {
        let shown = narrations.first { $0.id == chosen } ?? narrations.first
        ScrollView {
            VStack(spacing: 0) {
                if let shown {
                    AudiobookSeriesHeader(name: name, author: author, narration: shown)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    if narrations.count > 1 {
                        NarrationPills(names: narrations.map(\.id), selected: shown.id) { chosen = $0 }
                            .padding(.bottom, 16)
                    }
                    AudiobookSeriesGrid(narration: shown)
                        .padding(.horizontal, 16)
                }
            }
            .readableColumn()
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle(name)
        .toolbarTitleDisplayMode(.inline)
        // Again only when what's known of a book changes (Audible's answer
        // for one coming in).
        .onChange(of: details.books, initial: true) {
            narrations = Self.narrations(of: books)
        }
        .onAppear {
            details.request(books)
            // Every reading's covers, decoded ahead: a switch draws them at
            // once rather than loading each as its tile appears.
            ContentArtworkView.prefetch(books, preferredSize: 300)
            ContentArtworkView.prefetch(Self.narrations(of: books).flatMap { $0.books.prefix(3) }, preferredSize: 400)
        }
    }

    /// Who wrote the series: its first book's author.
    private var author: String? {
        books.first?.bookAuthor
    }
}

/// A series page's top: the reading's covers stacked, the series' name, who
/// wrote and reads it, and Play for the book to listen to next.
private struct AudiobookSeriesHeader: View {
    let name: String
    let author: String?
    let narration: AudiobookSeriesView.Narration

    var body: some View {
        VStack(spacing: 6) {
            StackedCovers(books: Array(narration.books.prefix(3)), size: 200)
                .padding(.bottom, 18)
            // New York for the series' name, as a book's page has its
            // title; rounded is set on each line under it, since the
            // outermost `.fontDesign` wins.
            Text(name)
                .font(.title.bold())
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
            if let author {
                Text(author)
                    .font(.body)
                    .fontDesign(.rounded)
            }
            // Always a line, so switching readings doesn't move what's
            // under it.
            Text(narration.id == AudiobookSeriesView.unknownReading ? "Narrator Unknown"
                 : narration.id == "Full Cast" ? "Full-Cast Edition" : "Narrated by \(narration.id)")
                .font(.subheadline)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Series · ^[\(narration.books.count) Audiobook](inflect: true)")
                .font(.subheadline)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
            AudiobookSeriesNextButton(narration: narration)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// Play for the book to listen to next: the one partway through, else the
/// first not finished. Its own view: it follows the places of the books,
/// which move every few seconds while one plays, and only it redraws.
private struct AudiobookSeriesNextButton: View {
    let narration: AudiobookSeriesView.Narration

    @State private var store = AudiobookProgressStore.shared

    var body: some View {
        let partway = narration.entries.first {
            guard let progress = store.progress(for: $0.book) else { return false }
            return progress.isStarted && !progress.isFinished
        }
        if let partway {
            AudiobookSeriesPlayButton(book: partway.book, label: "Continue \(partway.label)")
        } else if let first = narration.entries.first(where: { store.progress(for: $0.book)?.isFinished != true }) {
            AudiobookSeriesPlayButton(book: first.book, label: "Play \(first.label)")
        }
    }
}

/// A pill for each reading. One white capsule slides to the one picked
/// (it takes that pill's frame, `matchedGeometryEffect`), rather than one
/// fading out as another fades in, and the row resolves as one group.
private struct NarrationPills: View {
    let names: [String]
    let selected: String
    let pick: (String) -> Void

    @Namespace private var pills

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    let isSelected = name == selected
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        pick(name)
                    } label: {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.rounded)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .foregroundStyle(isSelected ? Color.black : Color.primary)
                            .matchedGeometryEffect(id: name, in: pills)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            // Every pill's grey under the white one, so the white isn't
            // tinted by the grey of the pill it's on.
            .background {
                ForEach(names, id: \.self) { name in
                    Capsule()
                        .fill(.fill.tertiary)
                        .matchedGeometryEffect(id: name, in: pills, isSource: false)
                }
                Capsule()
                    .fill(.white)
                    .matchedGeometryEffect(id: selected, in: pills, isSource: false)
            }
            .geometryGroup()
            .padding(.horizontal, 16)
            .animation(.snappy(duration: 0.25), value: selected)
        }
        .scrollIndicators(.hidden)
    }
}

/// A reading's books as a grid, in their order.
private struct AudiobookSeriesGrid: View {
    let narration: AudiobookSeriesView.Narration

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)], spacing: 20) {
            ForEach(narration.entries) { entry in
                NavigationLink(value: RouterDestination.audiobookDetail(content: entry.book)) {
                    AudiobookSeriesTile(entry: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    AudiobookMenuItems(book: entry.book)
                } preview: {
                    ContentArtworkView(content: entry.book, showMusicSource: false, preferredSize: 400, cornerRadius: 8)
                        .frame(width: 240, height: 240)
                }
            }
        }
    }
}

/// A book in a series' grid: its cover, its place in the series, its title
/// and how far in. Reads only its own book's place.
private struct AudiobookSeriesTile: View {
    let entry: AudiobookSeriesView.Narration.Entry

    @State private var store = AudiobookProgressStore.shared

    var body: some View {
        let progress = store.progress(for: entry.book)
        VStack(alignment: .leading, spacing: 4) {
            ContentArtworkView(content: entry.book, showMusicSource: false, preferredSize: 300, cornerRadius: 6)
                .aspectRatio(1, contentMode: .fit)
            Text(entry.label.uppercased())
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(entry.book.title)
                .font(.footnote)
                .fontDesign(.serif)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let progress, progress.isStarted || progress.isFinished {
                AudiobookProgressBar(fraction: progress.isFinished ? 1 : progress.fraction ?? 0, height: 2)
                    .padding(.top, 2)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Up to three covers, the first in front and the others behind it, peeking
/// out either side, as Apple Books stacks a series.
struct StackedCovers: View {
    let books: [PlayableContent]
    let size: CGFloat

    var body: some View {
        ZStack {
            // Back to front: the second and third either side, then the first.
            ForEach(Array(books.enumerated().reversed()), id: \.element.id) { index, book in
                ContentArtworkView(content: book, showMusicSource: false, preferredSize: 400, cornerRadius: 6)
                    .frame(width: size, height: size)
                    .scaleEffect(index == 0 ? 1 : 0.85)
                    .offset(x: index == 0 ? 0 : (index == 1 ? -1 : 1) * size * 0.28)
                    .brightness(index == 0 ? 0 : -0.25)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .zIndex(index == 0 ? 1 : 0)
            }
        }
        .frame(width: size * 1.56, height: size)
        .accessibilityHidden(true)
    }
}

/// The series page's Play: the book to listen to next, from where it was
/// left.
private struct AudiobookSeriesPlayButton: View {
    let book: PlayableContent
    let label: String

    @State private var isStarting = false

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            Task {
                isStarting = true
                await AudiobookPlayer.shared.play(book)
                isStarting = false
            }
        } label: {
            HStack(spacing: 8) {
                if isStarting {
                    ProgressView()
                } else {
                    Image(systemName: "play.fill")
                }
                Text(label)
            }
            .font(.headline)
            .fontDesign(.rounded)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.fill.tertiary, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
    }
}
