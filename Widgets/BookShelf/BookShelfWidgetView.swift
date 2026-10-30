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

    var body: some View {
        content
            .environment(\.shelfStyle, entry.style)
            .widgetURL(widgetURL)
            .containerBackground(for: .widget) {
                background
                    .environment(\.shelfStyle, entry.style)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            SmallBookView(entry: entry, coverIsBackground: coverIsBackground)
        case .systemMedium where !entry.isOne:
            Bookcase(entry: entry, showsLead: false)
        case .accessoryCircular:
            CircularBookView(entry: entry)
        case .accessoryRectangular:
            RectangularBookView(entry: entry)
        case .accessoryInline:
            InlineBookView(entry: entry)
        default:
            if entry.isOne {
                OneBookView(entry: entry)
            } else {
                // Large, extra large, and iOS 27's extra large portrait.
                Bookcase(entry: entry, showsLead: true)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .systemSmall:
            if let book = entry.books.first {
                BookCover(book: book)
            } else {
                ShelfBackground(look: entry.style.look)
            }
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            ShelfBackground(look: entry.style.look, book: entry.books.first)
        }
    }

    /// The small widget's cover fills it as its background, unless the
    /// background is taken away (a tinted or clear Home Screen, StandBy):
    /// then it's drawn as the content.
    private var coverIsBackground: Bool {
        renderingMode == .fullColor && showsBackground
    }

    /// Where a tap that no book or button takes goes: on a small widget, the
    /// Lock Screen's and One Book, which are one book, that book, as the
    /// widget is set; else the Audiobooks tab. A One Book whose cover and
    /// Play play it where it is opens its page around them, rather than
    /// opening Cue to play it.
    private var widgetURL: URL {
        let isAccessory = switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
        let isOneBook = isAccessory || family == .systemSmall || entry.isOne
        guard isOneBook, let book = entry.books.first else { return entry.heading.appLink }
        let style = entry.style
        switch style.action {
        case .play: return style.link(to: book.id, play: isAccessory || !style.playsInBackground)
        case .open: return style.link(to: book.id, play: false)
        case .openApp: return entry.heading.appLink
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
            BookTap(book: book) {
                face(of: book)
            }
        } else {
            ShelfMessage(entry: entry, isCompact: true)
                .padding(12)
        }
    }

    private func face(of book: ShelfBook) -> some View {
        let mark = style.coverMark(isPlaying: entry.state.isPlaying(book), isLoaded: entry.state.loadedID == book.id)
        return ZStack(alignment: .topTrailing) {
            if coverIsBackground {
                Color.clear
            } else {
                BookCover(book: book)
            }
            if let mark {
                CoverMark(symbol: mark, size: 30)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if style.showsProgress, let fraction = book.fraction {
                ProgressPill(fraction: fraction)
                    .padding(10)
            }
            if let speaker = entry.state.speaker {
                SpeakerPill(name: speaker)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
            let hasLead = showsLead && !entry.books.isEmpty
            // Where Play goes: in the header, which a shelf without a name
            // (My Shelf) shows for it alone, unless the lead can say it
            // under its Play.
            let headerSpeaker = entry.heading.showsHeader || !hasLead ? entry.state.speaker : nil
            let showsHeader = entry.heading.showsHeader || headerSpeaker != nil
            let metrics = BookcaseMetrics(size: proxy.size, margins: margins, look: style.look, showsLead: hasLead, showsHeader: showsHeader)
            let shelves = Shelves(books: entry.books, metrics: metrics)
            VStack(alignment: .leading, spacing: 0) {
                if showsHeader {
                    ShelfHeader(heading: entry.heading, speaker: headerSpeaker)
                        .frame(height: BookcaseMetrics.headerHeight)
                        .padding(.horizontal, metrics.inset)
                }
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
                        Spacer(minLength: metrics.headerGap)
                        LeadShelf(book: lead, beside: shelves.besideLead, state: entry.state, metrics: metrics, speaker: headerSpeaker == nil ? entry.state.speaker : nil, leavesCorner: !showsHeader)
                    }
                    ForEach(shelves.rows.indices, id: \.self) { index in
                        Spacer(minLength: index == 0 && shelves.lead == nil ? metrics.headerGap : BookcaseMetrics.rowGap)
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
            // Cue's glyph is the header's last; without one, in the corner.
            .overlay(alignment: .topTrailing) {
                if !showsHeader {
                    CueGlyph()
                        .padding(.top, metrics.top)
                        .padding(.trailing, metrics.inset)
                }
            }
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

    /// From the header to the first shelf; nothing without a header.
    let headerGap: CGFloat

    /// `showsHeader`: the shelf's name over it, or the shelves from the top
    /// (My Shelf, whose albums name themselves).
    init(size: CGSize, margins: EdgeInsets, look: ShelfLook, showsLead: Bool, showsHeader: Bool = true) {
        let header = showsHeader ? Self.headerHeight : 0
        let headerGap = showsHeader ? Self.headerGap : 0
        self.headerGap = headerGap
        // The system's margins, which `contentMarginsDisabled` leaves to the
        // views; 16 where it reports none.
        inset = margins.leading > 0 ? margins.leading : 16
        top = margins.top > 0 ? margins.top : 16
        // The last plank sits a little nearer the foot than the header to
        // the top: its shadow takes the rest.
        bottom = max((margins.bottom > 0 ? margins.bottom : 16) - 6, 8)
        let width = size.width - inset * 2
        let available = size.height - top - header - bottom
        let gap = look.gap
        let footprint = look.footprint
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
            let firstLead = min(width * 0.42 / footprint, 150, available - headerGap - plank - row)
            rows = max(0, Int((available - headerGap - firstLead - plank) / row))
            leadSide = max(min(width * 0.46 / footprint, 170, available - headerGap - plank - CGFloat(rows) * row), 44)
            // On a wide widget, books after the details on the lead's shelf.
            let room = width - leadSide * footprint - Self.leadSpacing - Self.detailsWidth - Self.leadSpacing
            besideLead = room >= side * footprint ? 1 + Int((room - side * footprint) / (side * footprint + gap)) : 0
        } else {
            // Without a header, Cue's glyph has the top corner.
            let corner = showsHeader ? 0 : CueGlyph.room
            let byHeight = available - headerGap - corner - plank
            side = max(min(byHeight, threeAcross, 120), 30)
            across = max(1, Int((width + gap) / (side * footprint + gap)))
            rows = max(1, Int((available - headerGap - corner + Self.rowGap) / (side + plank + Self.rowGap)))
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
    /// The Sonos group Play goes to, where the header doesn't say it.
    var speaker: String?
    /// Cue's glyph is in the corner over the details.
    var leavesCorner = false

    var body: some View {
        ShelfRow(inset: metrics.inset) {
            HStack(alignment: .bottom, spacing: BookcaseMetrics.leadSpacing) {
                BookTap(book: book) {
                    BookOnShelf(book: book, side: metrics.leadSide, isPlaying: state.isPlaying(book), isLoaded: state.loadedID == book.id, showsBar: false)
                }
                BookDetails(book: book, state: state, isRoomy: metrics.leadSide >= 130, speaker: speaker, leavesCorner: leavesCorner)
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
/// then how far in over Play, which says what's left of it.
private struct BookDetails: View {
    let book: ShelfBook
    let state: BookShelfWidgetState
    let isRoomy: Bool
    /// The Sonos group Play goes to, under it; nil where the header says it.
    var speaker: String?
    /// Keeps the title clear of the widget's top corner, Cue's glyph's.
    var leavesCorner = false

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
            VStack(alignment: .leading, spacing: 3) {
                if state.loadedID == book.id, let chapter = state.chapter {
                    Label(chapter, systemImage: isPlaying ? "waveform" : "bookmark.fill")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .widgetAccentable()
                }
                // New York for a book, rounded for an album (`titleDesign`).
                Text(book.title)
                    .font(.system(titleStyle, design: style.titleDesign, weight: .bold))
                    .foregroundStyle(primary)
                    .lineLimit(isRoomy ? 3 : 2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.trailing, leavesCorner ? CueGlyph.room : 0)
            if !book.author.isEmpty {
                Text(book.author)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 7) {
                if style.showsProgress, let fraction = book.fraction {
                    ProgressCapsule(fraction: fraction, track: secondary.opacity(0.35), fill: primary)
                        .frame(height: 4)
                }
                PlayPauseCapsule(book: book, isPlaying: isPlaying, isRoomy: isRoomy)
                if let speaker {
                    SpeakerLabel(name: speaker, color: secondary)
                }
            }
            .frame(maxWidth: 240, alignment: .leading)
        }
        // Clear of the plank's top, where the books stand.
        .padding(.bottom, ShelfPlank.standing + 6)
    }
}

/// Where Play goes while it's a Sonos group, by its name: the widget's
/// Play reaches the speaker, as Cue's own does, and says so.
struct SpeakerLabel: View {
    let name: String
    let color: Color

    var body: some View {
        Label(name, systemImage: "hifispeaker.fill")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel("Plays on \(name)")
    }
}

/// The shelf's name, in New York for books, and Cue's glyph, with
/// `speaker`, the Sonos group Play goes to, before it; for a shelf without
/// a name of its own (My Shelf), the speaker and glyph alone.
private struct ShelfHeader: View {
    let heading: ShelfHeading
    var speaker: String?

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isFullColor = renderingMode == .fullColor
        let secondary = isFullColor ? style.look.palette.secondaryText : Color.secondary
        HStack(spacing: 8) {
            if heading.showsHeader {
                Text(heading.title)
                    .font(.system(.headline, design: style.titleDesign, weight: .bold))
                    .foregroundStyle(isFullColor ? style.look.palette.text : Color.primary)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
            if let speaker {
                SpeakerLabel(name: speaker, color: secondary)
            }
            CueGlyph()
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
            Image(systemName: entry.state.needsServer ? "books.vertical" : entry.heading.symbol)
                .font(isCompact ? .title3 : .title2)
                .widgetAccentable()
            if !isCompact {
                Text(title)
                    .font(.system(.headline, design: style.titleDesign, weight: .bold))
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
        if entry.isUnwritten { return entry.heading.unwrittenTitle }
        if entry.state.needsServer { return "No Audiobooks Yet" }
        return entry.heading.emptyTitle ?? entry.heading.title
    }

    private var message: String {
        if entry.isUnwritten { return entry.heading.unwrittenMessage }
        if entry.state.needsServer { return "Sign in to Plex or Audiobookshelf in Cue to listen to your books." }
        return entry.heading.emptyMessage
    }
}

// MARK: - One Book

/// One book on its own (One Book), on every size but the small: no header,
/// its cover as big as the widget lets it be. On a wide widget (medium, an
/// iPad's extra large) its details stand beside it; on a tall one (large,
/// iOS 27's page-tall iPhone widget) how far in and Play stand beside it
/// and its title runs under it, and on the tallest the cover is centred,
/// Play going under too.
private struct OneBookView: View {
    let entry: BookShelfEntry

    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        if let book = entry.books.first {
            GeometryReader { proxy in
                let inset = margins.leading > 0 ? margins.leading : 16
                let top = margins.top > 0 ? margins.top : 16
                // As the bookcase's: the plank's shadow takes the rest.
                let bottom = max((margins.bottom > 0 ? margins.bottom : 16) - 6, 8)
                let width = proxy.size.width - inset * 2
                let height = proxy.size.height - top - bottom
                let plank = ShelfPlank.height - ShelfPlank.standing
                VStack(spacing: 0) {
                    if width > height * 1.25 {
                        wide(book, side: height - plank, inset: inset)
                    } else {
                        let isTallest = height > width * 1.5
                        // Room under the cover for the title block.
                        let side = min(width * (isTallest ? 0.8 : 0.56), height - plank - (isTallest ? 170 : 118))
                        tall(book, side: max(side, 60), inset: inset, isTallest: isTallest)
                    }
                }
                .padding(.top, top)
                .padding(.bottom, bottom)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .overlay(alignment: .topTrailing) {
                    CueGlyph()
                        .padding(.top, top)
                        .padding(.trailing, inset)
                }
            }
        } else {
            ShelfMessage(entry: entry, isCompact: false)
                .padding(16)
        }
    }

    private func wide(_ book: ShelfBook, side: CGFloat, inset: CGFloat) -> some View {
        ShelfRow(inset: inset) {
            HStack(alignment: .bottom, spacing: BookcaseMetrics.leadSpacing) {
                BookTap(book: book) {
                    BookOnShelf(book: book, side: side, isPlaying: entry.state.isPlaying(book), isLoaded: entry.state.loadedID == book.id, showsBar: false)
                }
                BookDetails(book: book, state: entry.state, isRoomy: side >= 130, speaker: entry.state.speaker, leavesCorner: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: side, alignment: .bottom)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func tall(_ book: ShelfBook, side: CGFloat, inset: CGFloat, isTallest: Bool) -> some View {
        let isPlaying = entry.state.isPlaying(book)
        return VStack(alignment: .leading, spacing: 0) {
            ShelfRow(inset: inset) {
                HStack(alignment: .bottom, spacing: BookcaseMetrics.leadSpacing) {
                    if isTallest {
                        Spacer(minLength: 0)
                    }
                    BookTap(book: book) {
                        BookOnShelf(book: book, side: side, isPlaying: isPlaying, isLoaded: entry.state.loadedID == book.id, showsBar: false)
                    }
                    if isTallest {
                        Spacer(minLength: 0)
                    } else {
                        BookStanding(book: book, isPlaying: isPlaying, speaker: entry.state.speaker)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: side, alignment: .bottom)
            }
            Spacer(minLength: 12)
            BookTitleBlock(book: book, state: entry.state, isPlayInline: isTallest)
                .padding(.horizontal, inset)
        }
    }
}

/// Beside a tall One Book's cover: how far in, over Play, which says
/// what's left.
private struct BookStanding: View {
    let book: ShelfBook
    let isPlaying: Bool
    /// The Sonos group Play goes to, if it's one.
    var speaker: String?

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isFullColor = renderingMode == .fullColor
        let palette = style.look.palette
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            if style.showsProgress, let fraction = book.fraction, !book.isFinished {
                Text(BookShelfFormat.percent(fraction))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: fraction))
                    .foregroundStyle(isFullColor ? palette.text : Color.primary)
                    .widgetAccentable()
            }
            PlayPauseCapsule(book: book, isPlaying: isPlaying)
                .padding(.top, 6)
            if let speaker {
                SpeakerLabel(name: speaker, color: isFullColor ? palette.secondaryText : Color.secondary)
                    .padding(.top, 4)
            }
        }
        // Clear of the plank's top, where the book stands.
        .padding(.bottom, ShelfPlank.standing + 6)
    }
}

/// Under a tall One Book's cover: the chapter it's in while it's loaded,
/// its title and author, and how far in as a bar; on the tallest, Play,
/// which says what's left, under the bar.
private struct BookTitleBlock: View {
    let book: ShelfBook
    let state: BookShelfWidgetState
    let isPlayInline: Bool

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isFullColor = renderingMode == .fullColor
        let palette = style.look.palette
        let primary = isFullColor ? palette.text : Color.primary
        let secondary = isFullColor ? palette.secondaryText : Color.secondary
        let isPlaying = state.isPlaying(book)
        VStack(alignment: .leading, spacing: 3) {
            if state.loadedID == book.id, let chapter = state.chapter {
                Label(chapter, systemImage: isPlaying ? "waveform" : "bookmark.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            // New York for a book, rounded for an album (`titleDesign`).
            Text(book.title)
                .font(.system(.title3, design: style.titleDesign, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if !book.author.isEmpty {
                Text(book.author)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 7) {
                if style.showsProgress, let fraction = book.fraction {
                    ProgressCapsule(fraction: fraction, track: secondary.opacity(0.35), fill: primary)
                        .frame(height: 4)
                }
                if isPlayInline {
                    PlayPauseCapsule(book: book, isPlaying: isPlaying)
                    if let speaker = state.speaker {
                        SpeakerLabel(name: speaker, color: secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
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
                // The Sonos group Play goes to leads, ahead of the chapter
                // or author.
                let line = entry.state.speaker.map { Text("\(Image(systemName: "hifispeaker.fill")) \($0) · \(detail)") } ?? Text(detail)
                line
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
                            .contentTransition(.numericText())
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
                Text(entry.state.needsServer ? "Sign in to a server in Cue." : entry.heading.emptyMessage)
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
