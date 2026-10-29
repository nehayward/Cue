import Defaults
import SwiftUI
import WidgetKit

/// The book shelf widget, by size. Every size but the small one and the
/// Lock Screen's is a bookcase (`Bookcase`): sized from the room the widget
/// has, so one layout serves a medium shelf, a large one, an iPad's wide
/// extra large and iOS 27's page-tall iPhone widget.
struct BookShelfWidgetView: View {
    let entry: BookShelfEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var style: ShelfStyle {
        ShelfStyle(entry.configuration)
    }

    var body: some View {
        content
            .environment(\.shelfStyle, style)
            .widgetURL(widgetURL)
            .containerBackground(for: .widget) {
                background
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            SmallBookView(entry: entry, coverIsBackground: coverIsBackground)
        case .systemMedium:
            Bookcase(entry: entry, showsLead: false)
        case .accessoryCircular:
            CircularBookView(entry: entry)
        case .accessoryRectangular:
            RectangularBookView(entry: entry)
        case .accessoryInline:
            InlineBookView(entry: entry)
        default:
            // Large, extra large, and iOS 27's extra large portrait.
            Bookcase(entry: entry, showsLead: true)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .systemSmall:
            if let book = entry.books.first {
                BookCover(book: book)
            } else {
                ShelfBackground(look: entry.configuration.look)
            }
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            ShelfBackground(look: entry.configuration.look)
        }
    }

    /// The small widget's cover fills it as its background, unless the
    /// background is taken away (a tinted or clear Home Screen, StandBy):
    /// then it's drawn as the content.
    private var coverIsBackground: Bool {
        renderingMode == .fullColor && showsBackground
    }

    /// Where a tap that no book or button takes goes: on a small widget and
    /// the Lock Screen's, which are one book, that book, as the widget is
    /// set; else the Audiobooks tab.
    private var widgetURL: URL {
        let isOneBook = switch family {
        case .systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
        guard isOneBook, let book = entry.books.first else { return BookShelfWidgetState.audiobooksLink }
        switch entry.configuration.action {
        case .playBook: return BookShelfWidgetState.link(to: book.id, play: true)
        case .openBook: return BookShelfWidgetState.link(to: book.id, play: false)
        case .openApp: return BookShelfWidgetState.audiobooksLink
        }
    }
}

// MARK: - Small

/// One book, its cover the whole widget, how far in at its corner.
private struct SmallBookView: View {
    let entry: BookShelfEntry
    let coverIsBackground: Bool

    @Environment(\.shelfStyle) private var style

    var body: some View {
        if let book = entry.books.first {
            if style.action == .playBook, style.playsInBackground {
                Button(intent: PlayBookIntent(bookID: book.id)) {
                    face(of: book)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(book.title)")
            } else {
                face(of: book)
            }
        } else {
            ShelfMessage(entry: entry, isCompact: true)
                .padding(12)
        }
    }

    private func face(of book: ShelfBook) -> some View {
        let isPlaying = entry.state.isPlaying(book)
        return ZStack(alignment: .topTrailing) {
            if coverIsBackground {
                Color.clear
            } else {
                BookCover(book: book)
            }
            if style.showsProgress, let fraction = book.fraction {
                ProgressPill(fraction: fraction, isPlaying: isPlaying)
                    .padding(10)
            } else if isPlaying {
                PlayingBadge(size: 26)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }
}

// MARK: - Bookcase

/// The shelves of every size but the small: the shelf's name, then, with
/// `showsLead`, its first book on display with its title, how far in and
/// Play beside it (more books after them on a wide widget), then as many
/// shelves of books as the widget has room for. Shelves with no books left
/// for them stay, empty, as a bookcase's do.
private struct Bookcase: View {
    let entry: BookShelfEntry
    let showsLead: Bool

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        GeometryReader { proxy in
            let metrics = BookcaseMetrics(size: proxy.size, margins: margins, look: style.look, showsLead: showsLead && !entry.books.isEmpty)
            let shelves = Shelves(books: entry.books, metrics: metrics)
            VStack(alignment: .leading, spacing: 0) {
                ShelfHeader(option: entry.configuration.shelf)
                    .frame(height: BookcaseMetrics.headerHeight)
                    .padding(.horizontal, metrics.inset)
                if entry.books.isEmpty {
                    Spacer(minLength: 4)
                    ShelfMessage(entry: entry, isCompact: proxy.size.height < 200)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, metrics.inset)
                    Spacer(minLength: 4)
                    ShelfRow(inset: metrics.inset) {
                        Color.clear
                            .frame(height: 1)
                    }
                } else {
                    if let lead = shelves.lead {
                        Spacer(minLength: BookcaseMetrics.headerGap)
                        LeadShelf(book: lead, beside: shelves.besideLead, state: entry.state, metrics: metrics)
                    }
                    ForEach(shelves.rows.indices, id: \.self) { index in
                        Spacer(minLength: index == 0 && shelves.lead == nil ? BookcaseMetrics.headerGap : BookcaseMetrics.rowGap)
                        ShelfRow(inset: metrics.inset) {
                            ShelfBooks(books: shelves.rows[index], side: metrics.side, state: entry.state)
                                .frame(height: metrics.side, alignment: .bottomLeading)
                        }
                    }
                }
            }
            .padding(.top, metrics.top)
            .padding(.bottom, metrics.bottom)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

/// How big the books are and how many fit, from the widget's size.
struct BookcaseMetrics {
    static let headerHeight: CGFloat = 22
    /// From the header to the first shelf's tallest book, at least.
    static let headerGap: CGFloat = 10
    /// From a plank to the books on the shelf below, at least.
    static let rowGap: CGFloat = 12
    /// The least room the lead book's details get beside it before books
    /// stand there too.
    static let detailsWidth: CGFloat = 250
    /// From the lead book to its details.
    static let leadSpacing: CGFloat = 14

    /// In from the widget's sides, and from its top and bottom.
    let inset: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    /// A book on the shelves, and how many stand on each.
    let side: CGFloat
    let across: Int
    /// The shelves of books, besides the lead's.
    let rows: Int
    /// The lead book; zero with none.
    let leadSide: CGFloat
    /// Books after the lead's details, on its shelf.
    let besideLead: Int

    init(size: CGSize, margins: EdgeInsets, look: BookShelfLook, showsLead: Bool) {
        // The system's margins, which `contentMarginsDisabled` leaves to the
        // views; 16 where it reports none.
        inset = margins.leading > 0 ? margins.leading : 16
        top = margins.top > 0 ? margins.top : 16
        // The last plank sits a little nearer the foot than the header to
        // the top: its shadow takes the rest.
        bottom = max((margins.bottom > 0 ? margins.bottom : 16) - 6, 8)
        let width = size.width - inset * 2
        let available = size.height - top - Self.headerHeight - bottom
        let footprint = look.footprint
        let gap = look.gap
        // What a shelf adds under its books.
        let plank = ShelfPlank.height - ShelfPlank.standing
        // Three across on a narrow widget; no bigger than 100 on a wide one.
        let threeAcross = (width - gap * 2) / (footprint * 3)

        if showsLead {
            side = max(min(threeAcross, 100), 30)
            across = max(1, Int((width + gap) / (side * footprint + gap)))
            let row = side + plank + Self.rowGap
            // The lead first, as big as it may be with one shelf under it;
            // then the shelves that fit under that; then the lead as big as
            // the room they leave.
            let firstLead = min(width * 0.42 / footprint, 150, available - Self.headerGap - plank - row)
            rows = max(0, Int((available - Self.headerGap - firstLead - plank) / row))
            leadSide = max(min(width * 0.46 / footprint, 170, available - Self.headerGap - plank - CGFloat(rows) * row), 44)
            // On a wide widget, books after the details on the lead's shelf.
            let room = width - leadSide * footprint - Self.leadSpacing - Self.detailsWidth - Self.leadSpacing
            besideLead = room >= side * footprint ? 1 + Int((room - side * footprint) / (side * footprint + gap)) : 0
        } else {
            let byHeight = available - Self.headerGap - plank
            side = max(min(byHeight, threeAcross, 120), 30)
            across = max(1, Int((width + gap) / (side * footprint + gap)))
            rows = max(1, Int((available - Self.headerGap + Self.rowGap) / (side + plank + Self.rowGap)))
            leadSide = 0
            besideLead = 0
        }
    }
}

/// The shelf's books, dealt out to the bookcase: the lead, those beside
/// it, then a shelf at a time.
private struct Shelves {
    let lead: ShelfBook?
    let besideLead: ArraySlice<ShelfBook>
    let rows: [ArraySlice<ShelfBook>]

    init(books: [ShelfBook], metrics: BookcaseMetrics) {
        var start = 0
        if metrics.leadSide > 0, let first = books.first {
            lead = first
            start = 1
        } else {
            lead = nil
        }
        func next(_ count: Int) -> ArraySlice<ShelfBook> {
            let slice = books[min(start, books.count) ..< min(start + count, books.count)]
            start += count
            return slice
        }
        besideLead = next(lead == nil ? 0 : metrics.besideLead)
        rows = (0 ..< metrics.rows).map { _ in next(metrics.across) }
    }
}

/// The lead book standing on its own shelf, its details beside it, and on a
/// wide widget more books after them.
private struct LeadShelf: View {
    let book: ShelfBook
    let beside: ArraySlice<ShelfBook>
    let state: BookShelfWidgetState
    let metrics: BookcaseMetrics

    var body: some View {
        ShelfRow(inset: metrics.inset) {
            HStack(alignment: .bottom, spacing: BookcaseMetrics.leadSpacing) {
                BookTap(book: book) {
                    BookOnShelf(book: book, side: metrics.leadSide, isPlaying: state.isPlaying(book))
                }
                BookDetails(book: book, state: state, isRoomy: metrics.leadSide >= 130)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                if !beside.isEmpty {
                    ShelfBooks(books: beside, side: metrics.side, state: state)
                }
            }
            .frame(height: metrics.leadSide, alignment: .bottom)
        }
    }
}

/// The lead book's title, author, the chapter it's in while it's loaded,
/// how far in, and Play.
private struct BookDetails: View {
    let book: ShelfBook
    let state: BookShelfWidgetState
    let isRoomy: Bool

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isFullColor = renderingMode == .fullColor
        let palette = style.look.palette
        let primary = isFullColor ? palette.text : Color.primary
        let secondary = isFullColor ? palette.secondaryText : Color.secondary
        let isPlaying = state.isPlaying(book)
        let titleStyle: Font.TextStyle = isRoomy ? .title3 : .headline
        VStack(alignment: .leading, spacing: 3) {
            if state.loadedID == book.id, let chapter = state.chapter {
                Label(chapter, systemImage: isPlaying ? "waveform" : "bookmark.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            // New York, a book's own face, as in Cue.
            Text(book.title)
                .font(.system(titleStyle, design: .serif, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(isRoomy ? 3 : 2)
                .minimumScaleFactor(0.85)
            if !book.author.isEmpty {
                Text(book.author)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                PlayPauseButton(book: book, isPlaying: isPlaying, size: isRoomy ? 38 : 32)
                VStack(alignment: .leading, spacing: 5) {
                    if style.showsProgress, let fraction = book.fraction {
                        ProgressCapsule(fraction: fraction, track: secondary.opacity(0.35), fill: primary)
                            .frame(height: 4)
                    }
                    if let left = BookShelfFormat.timeLeft(book) {
                        Text(left)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
        // Clear of the plank's top, where the books stand.
        .padding(.bottom, ShelfPlank.standing + 6)
    }
}

/// The shelf's name, in New York, with its mark.
private struct ShelfHeader: View {
    let option: BookShelfOption

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isFullColor = renderingMode == .fullColor
        HStack(alignment: .firstTextBaseline) {
            Text(option.title)
                .font(.system(.headline, design: .serif, weight: .bold))
                .foregroundStyle(isFullColor ? style.look.palette.text : Color.primary)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 8)
            Image(systemName: option.symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(isFullColor ? style.look.palette.secondaryText : Color.secondary)
        }
    }
}

/// What an empty shelf says: open Cue (it hasn't written its shelves yet),
/// sign in to a server for books, or what the shelf will hold.
private struct ShelfMessage: View {
    let entry: BookShelfEntry
    let isCompact: Bool

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isFullColor = renderingMode == .fullColor
        VStack(spacing: isCompact ? 4 : 6) {
            Image(systemName: entry.state.needsServer ? "books.vertical" : entry.configuration.shelf.symbol)
                .font(isCompact ? .title3 : .title2)
                .widgetAccentable()
            if !isCompact {
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .bold))
            }
            Text(message)
                .font(.system(.caption, design: .rounded))
                .opacity(0.75)
                .lineLimit(isCompact ? 4 : 3)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(isFullColor ? style.look.palette.text : Color.primary)
    }

    private var title: String {
        if entry.isUnwritten { return "Your Audiobooks" }
        if entry.state.needsServer { return "No Audiobooks Yet" }
        return entry.configuration.shelf.title
    }

    private var message: String {
        if entry.isUnwritten { return "Open Cue to put your books on this shelf." }
        if entry.state.needsServer { return "Sign in to Plex or Audiobookshelf in Cue to listen to your books." }
        return entry.configuration.shelf.emptyMessage
    }
}

// MARK: - Lock Screen

/// The first book's progress as a ring.
private struct CircularBookView: View {
    let entry: BookShelfEntry

    var body: some View {
        if let book = entry.books.first {
            Gauge(value: book.fraction ?? 0) {
                Image(systemName: "book.closed.fill")
            } currentValueLabel: {
                if entry.state.isPlaying(book) {
                    Image(systemName: "waveform")
                } else if let fraction = book.fraction {
                    Text(BookShelfFormat.percent(fraction))
                } else {
                    Image(systemName: "book.closed.fill")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(book.title)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
            }
        }
    }
}

/// The first book: its title, author or chapter, and how far in.
private struct RectangularBookView: View {
    let entry: BookShelfEntry

    @Environment(\.shelfStyle) private var style

    var body: some View {
        if let book = entry.books.first {
            let detail = entry.state.loadedID == book.id ? entry.state.chapter ?? book.author : book.author
            let left = BookShelfFormat.timeLeft(book)
            VStack(alignment: .leading, spacing: 2) {
                Label(book.title, systemImage: entry.state.isPlaying(book) ? "waveform" : "book.closed.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if style.showsProgress, let fraction = book.fraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    }
                    if let left {
                        Text(left)
                            .font(.caption2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Audiobooks", systemImage: "books.vertical.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.state.needsServer ? "Sign in to a server in Cue." : entry.configuration.shelf.emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The first book and how far in, on one line over the clock.
private struct InlineBookView: View {
    let entry: BookShelfEntry

    var body: some View {
        if let book = entry.books.first {
            let text = book.fraction.map { "\(book.title) · \(BookShelfFormat.percent($0))" } ?? book.title
            Label(text, systemImage: entry.state.isPlaying(book) ? "waveform" : "book.closed.fill")
        } else {
            Label("Audiobooks", systemImage: "books.vertical.fill")
        }
    }
}
