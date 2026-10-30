import Defaults
import SwiftUI
import UIKit
import WidgetKit

typealias ShelfBook = BookShelfWidgetState.Book

// MARK: - Style

/// Which widget the shelves are: the book shelf or the album shelf. It
/// decides what a tap runs and opens, and which App Group folder the
/// covers are in; the views are the same.
enum ShelfKind {
    case books
    case albums

    var folder: BookShelfWidgetState.Folder {
        switch self {
        case .books: .books
        case .albums: .albums
        }
    }
}

/// What a tap on a book or album does.
enum ShelfAction {
    /// Plays it, in Cue's process or opening Cue on the player.
    case play
    /// Opens its page in Cue.
    case open
    /// Opens Cue, the widget's own link.
    case openApp
}

/// How the shelves are drawn.
enum ShelfLook {
    /// Covers standing on walnut shelves.
    case bookshelf
    /// Rounded covers on frosted glass, no shelves.
    case glass
    /// Sleeves on a dark shelf, each with its record slid out.
    case records

    /// How much wider than its cover an item stands on the shelf: a
    /// record's disc shows past its sleeve.
    var footprint: CGFloat {
        self == .records ? 1.3 : 1
    }

    /// The room between two items on a shelf.
    var gap: CGFloat {
        self == .records ? 8 : 12
    }

    var palette: ShelfPalette {
        switch self {
        case .bookshelf: .walnut
        case .glass: .frost
        case .records: .ebony
        }
    }
}

/// The widget's settings, for the views deep in it.
struct ShelfStyle {
    var kind: ShelfKind = .books
    var look: ShelfLook = .bookshelf
    var action: ShelfAction = .play
    var playsInBackground = true
    var showsProgress = true

    /// Titles and headings: New York, a book's own face, for books; rounded,
    /// as Cue's music is set, for albums.
    var titleDesign: Font.Design {
        kind == .albums ? .rounded : .serif
    }

    /// The link that opens `id`'s page, or plays it and opens the player.
    func link(to id: String, play: Bool) -> URL {
        switch kind {
        case .books: BookShelfWidgetState.link(to: id, play: play)
        case .albums: BookShelfWidgetState.Albums.link(to: id, play: play)
        }
    }

    /// The mark on the loaded item's cover: where a tap on the cover plays
    /// and pauses it, Pause while it plays and Play while it's paused; else
    /// a waveform while it plays.
    func coverMark(isPlaying: Bool, isLoaded: Bool) -> String? {
        if action == .play {
            if isPlaying { return "pause.fill" }
            return isLoaded ? "play.fill" : nil
        }
        return isPlaying ? "waveform" : nil
    }
}

extension EnvironmentValues {
    @Entry var shelfStyle: ShelfStyle = ShelfStyle()
}

/// What a shelf is called and says while it's empty.
struct ShelfHeading {
    let title: String
    let symbol: String
    /// Over `emptyMessage`; the title where nil.
    var emptyTitle: String?
    let emptyMessage: String
    /// What an empty widget says before Cue has written its shelves.
    let unwrittenTitle: String
    let unwrittenMessage: String
    /// Where a tap that no item or button takes goes.
    let appLink: URL
    /// The name and mark over the shelves; off where the items are the
    /// widget's whole point (My Shelf).
    var showsHeader = true
}

/// The colours of a look, in full colour. A tinted or clear Home Screen
/// takes the background away and draws the rest in its own colour.
struct ShelfPalette {
    let backTop: Color
    let backBottom: Color
    let plankTop: Color
    let plankFront: Color
    let plankBottom: Color
    let text: Color
    let secondaryText: Color

    /// A record shelf: dark oak against a black wall.
    static let ebony = ShelfPalette(
        backTop: Color(red: 0.12, green: 0.12, blue: 0.13),
        backBottom: Color(red: 0.04, green: 0.04, blue: 0.05),
        plankTop: Color(red: 0.45, green: 0.33, blue: 0.23),
        plankFront: Color(red: 0.30, green: 0.21, blue: 0.14),
        plankBottom: Color(red: 0.16, green: 0.11, blue: 0.07),
        text: .white,
        secondaryText: .white.opacity(0.6)
    )

    /// A walnut bookcase.
    static let walnut = ShelfPalette(
        backTop: Color(red: 0.25, green: 0.17, blue: 0.11),
        backBottom: Color(red: 0.14, green: 0.09, blue: 0.06),
        plankTop: Color(red: 0.74, green: 0.54, blue: 0.35),
        plankFront: Color(red: 0.55, green: 0.37, blue: 0.23),
        plankBottom: Color(red: 0.33, green: 0.21, blue: 0.13),
        text: Color(red: 1, green: 0.96, blue: 0.88),
        secondaryText: Color(red: 1, green: 0.96, blue: 0.88).opacity(0.66)
    )

    /// Glass: the system's own colours, so it's light or dark with the
    /// Home Screen. It has no planks.
    static let frost = ShelfPalette(
        backTop: Color(uiColor: .systemBackground),
        backBottom: Color(uiColor: .systemBackground),
        plankTop: .clear,
        plankFront: .clear,
        plankBottom: .clear,
        text: .primary,
        secondaryText: .secondary
    )
}

// MARK: - Background

/// The wall behind the shelves: the look's wood, its grain, and darker at
/// the edges; for glass, `book`'s cover frosted over.
struct ShelfBackground: View {
    let look: ShelfLook
    var book: ShelfBook?

    var body: some View {
        if look == .glass {
            FrostedBackground(book: book)
        } else {
            let palette = look.palette
            ZStack {
                LinearGradient(colors: [palette.backTop, palette.backBottom], startPoint: .top, endPoint: .bottom)
                WoodGrain(look: look)
                RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center, startRadius: 60, endRadius: 420)
            }
        }
    }
}

/// The glass look's back: the first book's cover blurred past knowing,
/// under a frost of the system's background, so the widget takes its
/// colour from the book on the go and is light or dark with the Home
/// Screen; lit a little from the top corner, as glass catches the light.
private struct FrostedBackground: View {
    let book: ShelfBook?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let book {
                BookCover(book: book)
                    // Opaque: its edges blur to the cover, not to clear.
                    .blur(radius: 50, opaque: true)
                    .saturation(1.4)
                Color(uiColor: .systemBackground)
                    .opacity(isDark ? 0.5 : 0.6)
            }
            LinearGradient(colors: [.white.opacity(isDark ? 0.1 : 0.3), .clear], startPoint: .topLeading, endPoint: .center)
        }
    }
}

/// Fine streaks running across the wall, the same every time for a look.
private struct WoodGrain: View {
    let look: ShelfLook

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(seed: look == .records ? 0x85EB_CA6B : 0x9E37_79B9)
            // The record shelf's wall is black and barely shows it.
            let strength: Double = look == .records ? 0.4 : 1
            var y: CGFloat = 0
            while y < size.height {
                let width = CGFloat(0.5 + random.next() * 1.6)
                let opacity = (0.015 + random.next() * 0.05) * strength
                let isLight = random.next() > 0.55
                let amplitude = CGFloat(random.next() * 2.5)
                let phase = CGFloat(random.next() * .pi * 2)
                let wavelength = CGFloat(40 + random.next() * 60)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y + amplitude * sin(phase)))
                var x: CGFloat = 8
                while x <= size.width + 8 {
                    path.addLine(to: CGPoint(x: x, y: y + amplitude * sin(x / wavelength + phase)))
                    x += 8
                }
                let color: Color = isLight ? .white.opacity(opacity) : .black.opacity(opacity * 1.8)
                context.stroke(path, with: .color(color), lineWidth: width)
                y += CGFloat(2 + random.next() * 7)
            }
        }
    }
}

/// A linear congruential generator: the grain comes out the same on every
/// reload.
private struct SeededRandom {
    var seed: UInt64

    /// 0..<1.
    mutating func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Shelves

/// A plank: its top, where the books stand, lit from above, its front
/// edge, and its shadow on the wall below. On a tinted Home Screen, a line;
/// on glass, only the room one takes.
struct ShelfPlank: View {
    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    static let height: CGFloat = 12
    /// How far the books stand into its top.
    static let standing: CGFloat = 3

    var body: some View {
        if style.look == .glass {
            Color.clear
                .frame(height: Self.height)
        } else if renderingMode == .fullColor {
            let palette = style.look.palette
            VStack(spacing: 0) {
                LinearGradient(colors: [palette.plankTop.opacity(0.75), palette.plankTop], startPoint: .top, endPoint: .bottom)
                    .frame(height: 4)
                LinearGradient(colors: [palette.plankFront, palette.plankBottom], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.height - 4)
            }
            // The front edge catching the light.
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.22))
                    .frame(height: 0.5)
                    .offset(y: 4)
            }
            .background(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .offset(y: 14)
            }
        } else {
            Capsule()
                .fill(Color.primary.opacity(0.25))
                .frame(height: 3)
                .padding(.vertical, (Self.height - 3) / 2)
        }
    }
}

/// Books standing on a plank that runs the widget's width; `inset` keeps
/// them in from its edges.
struct ShelfRow<Books: View>: View {
    let inset: CGFloat
    @ViewBuilder let books: Books

    var body: some View {
        VStack(spacing: -ShelfPlank.standing) {
            books
                .padding(.horizontal, inset)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                // In front of the plank's top: standing on it.
                .zIndex(1)
            ShelfPlank()
        }
    }
}

/// A row of books, each as big as `side`, from the left.
struct ShelfBooks: View {
    let books: ArraySlice<ShelfBook>
    let side: CGFloat
    let state: BookShelfWidgetState

    @Environment(\.shelfStyle) private var style

    var body: some View {
        HStack(alignment: .bottom, spacing: style.look.gap) {
            ForEach(books) { book in
                BookTap(book: book) {
                    BookOnShelf(book: book, side: side, isPlaying: state.isPlaying(book), isLoaded: state.loadedID == book.id)
                }
            }
        }
    }
}

// MARK: - A book

/// A book as it stands on the shelf: a hardcover with its spine catching
/// the light, a rounded tile edged like glass, or an album's sleeve with
/// its record slid out; how far in along its foot.
struct BookOnShelf: View {
    let book: ShelfBook
    let side: CGFloat
    let isPlaying: Bool
    /// The book loaded to play, playing or paused.
    var isLoaded = false
    /// How far in along its foot; off where it's beside the cover (the
    /// lead, One Book). A finished book's check stays.
    var showsBar = true

    @Environment(\.shelfStyle) private var style

    var body: some View {
        switch style.look {
        case .bookshelf:
            cover
                .overlay(alignment: .leading) {
                    // The spine's hinge.
                    LinearGradient(colors: [.white.opacity(0.3), .black.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(side * 0.05, 3))
                }
                .clipShape(.rect(cornerRadius: max(side * 0.03, 2)))
                .shadow(color: .black.opacity(0.5), radius: 2.5, x: 1, y: 1.5)
        case .glass:
            let radius = max(side * 0.08, 4)
            cover
                .clipShape(.rect(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
        case .records:
            RecordOnShelf(book: book, side: side, isPlaying: isPlaying) {
                cover
                    .clipShape(.rect(cornerRadius: 1.5))
            }
        }
    }

    private var cover: some View {
        BookCover(book: book)
            .frame(width: side, height: side)
            .overlay(alignment: .bottom) {
                if style.showsProgress {
                    CoverProgress(book: book, side: side, showsBar: showsBar)
                }
            }
            .overlay(alignment: .topLeading) {
                if let mark = style.coverMark(isPlaying: isPlaying, isLoaded: isLoaded) {
                    CoverMark(symbol: mark, size: max(side * 0.24, 18))
                        .padding(max(side * 0.05, 4))
                }
            }
    }
}

/// A sleeve with its record out of it to the right, the one playing
/// further, under the sleeve beside it.
private struct RecordOnShelf<Sleeve: View>: View {
    let book: ShelfBook
    let side: CGFloat
    let isPlaying: Bool
    @ViewBuilder let sleeve: Sleeve

    var body: some View {
        let disc = side * 0.94
        let out: CGFloat = isPlaying ? 0.45 : 0.27
        ZStack(alignment: .leading) {
            Vinyl(book: book)
                .frame(width: disc, height: disc)
                .offset(x: side * out + (side - disc) / 2)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
            sleeve
                .shadow(color: .black.opacity(0.55), radius: 2.5, x: 1, y: 1.5)
        }
        .frame(width: side * ShelfLook.records.footprint, height: side, alignment: .leading)
    }
}

/// A black record, its grooves catching the light, the cover on its label.
private struct Vinyl: View {
    let book: ShelfBook

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.06))
            ForEach(0 ..< 6, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                    .scaleEffect(0.48 + CGFloat(ring) * 0.09)
            }
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.18), .clear, .clear, .white.opacity(0.12), .clear], center: .center))
            BookCover(book: book)
                .clipShape(.circle)
                .scaleEffect(0.36)
            Circle()
                .fill(Color(white: 0.06))
                .scaleEffect(0.04)
        }
    }
}

/// `book`'s cover as Cue left it in the App Group, else one drawn for it.
/// It takes the room it's offered and no more: a cover that isn't square
/// is cropped to it, rather than growing what it's in past the widget.
struct BookCover: View {
    let book: ShelfBook

    @Environment(\.shelfStyle) private var style

    var body: some View {
        Color.clear
            .overlay {
                if let name = book.cover, let image = BookCoverImages.image(named: name, in: style.kind.folder) {
                    Image(uiImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                } else {
                    GeneratedCover(title: book.title, author: book.author)
                }
            }
            .clipped()
    }
}

/// Covers decoded once a render: the lead's is drawn twice on Glass (on the
/// shelf and blurred behind it). A cover's file name changes with it, so a
/// name never stands for an older picture.
enum BookCoverImages {
    private static let decoded = NSCache<NSString, UIImage>()

    static func image(named name: String, in folder: BookShelfWidgetState.Folder) -> UIImage? {
        let key = "\(folder.rawValue)/\(name)" as NSString
        if let image = decoded.object(forKey: key) { return image }
        guard let url = BookShelfWidgetState.coverURL(named: name, in: folder), let image = UIImage(contentsOfFile: url.path) else { return nil }
        decoded.setObject(image, forKey: key)
        return image
    }
}

/// A cloth cover with the title stamped on it, for a book with no cover of
/// its own and the gallery's made-up books. Its colour comes from the
/// title, so a book keeps it.
struct GeneratedCover: View {
    let title: String
    let author: String

    @Environment(\.shelfStyle) private var style

    private static let cloths: [Color] = [
        Color(red: 0.45, green: 0.12, blue: 0.13),
        Color(red: 0.12, green: 0.20, blue: 0.36),
        Color(red: 0.13, green: 0.30, blue: 0.22),
        Color(red: 0.62, green: 0.45, blue: 0.15),
        Color(red: 0.10, green: 0.33, blue: 0.36),
        Color(red: 0.33, green: 0.16, blue: 0.33),
        Color(red: 0.20, green: 0.20, blue: 0.22),
        Color(red: 0.55, green: 0.25, blue: 0.14),
    ]
    private static let foil = Color(red: 0.93, green: 0.84, blue: 0.62)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Self.cloths[Self.index(of: title)]
                Rectangle()
                    .strokeBorder(Self.foil.opacity(0.55), lineWidth: max(side * 0.008, 0.5))
                    .padding(side * 0.06)
                // Too small to read, the cloth alone.
                if side >= 44 {
                    VStack(spacing: side * 0.05) {
                        Text(title)
                            .font(.system(size: side * 0.13, weight: .semibold, design: style.titleDesign))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .minimumScaleFactor(0.6)
                        Rectangle()
                            .fill(Self.foil.opacity(0.7))
                            .frame(width: side * 0.18, height: max(side * 0.008, 0.5))
                        Text(author)
                            .font(.system(size: side * 0.07, weight: .medium, design: .rounded))
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Self.foil)
                    .padding(side * 0.12)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private static func index(of title: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in title.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return Int(hash % UInt64(cloths.count))
    }
}

// MARK: - Progress

/// How far in, along a cover's foot: a bar, or a check once it's finished.
private struct CoverProgress: View {
    let book: ShelfBook
    let side: CGFloat
    var showsBar = true

    var body: some View {
        if book.isFinished {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.system(size: max(side * 0.16, 11)))
                    .widgetAccentable()
            }
            .padding(max(side * 0.05, 4))
        } else if showsBar, let fraction = book.fraction {
            ProgressCapsule(fraction: fraction)
                .frame(height: max(side * 0.035, 3))
                .padding(.horizontal, max(side * 0.07, 5))
                .padding(.bottom, max(side * 0.07, 5))
        }
    }
}

/// A thin bar, filled as far as `fraction`.
struct ProgressCapsule: View {
    let fraction: Double
    var track: Color = .black.opacity(0.45)
    var fill: Color = .white

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(proxy.size.width * CGFloat(fraction), proxy.size.height))
                    .widgetAccentable()
            }
        }
    }
}

/// A ring and the percentage beside it, on the small widget's cover.
struct ProgressPill: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            .frame(width: 15, height: 15)
            Text(BookShelfFormat.percent(fraction))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: fraction))
        }
        .foregroundStyle(.white)
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.45), in: .capsule)
    }
}

/// Where Play goes while it's a Sonos group, on the small widget's cover:
/// the group's name in a dark capsule, as `ProgressPill` is drawn.
struct SpeakerPill: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "hifispeaker.fill")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.45), in: .capsule)
            .accessibilityLabel("Plays on \(name)")
    }
}

/// The loaded book's mark on its cover (`ShelfStyle.coverMark`): Pause,
/// Play or a waveform in a dark circle.
struct CoverMark: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * (symbol == "waveform" ? 0.5 : 0.42), weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(.white)
            // The play triangle sits a touch right of centre to look centred.
            .offset(x: symbol == "play.fill" ? size * 0.04 : 0)
            .frame(width: size, height: size)
            .background(.black.opacity(0.55), in: .circle)
            .widgetAccentable()
            // Dimmed from a tap until Cue's write after it lands.
            .invalidatableContent()
            .accessibilityLabel(symbol == "pause.fill" ? "Playing, tap to pause" : symbol == "play.fill" ? "Paused, tap to play" : "Playing")
    }
}

enum BookShelfFormat {
    /// "42%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "5h 3m", "42m": how long, to the minute, in the narrow form, as
    /// Cue's own lists put it.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), seconds > 0 ? 1 : 0)
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// What's left ("5h 3m left"), that it's finished, or before it's
    /// started, how long it is.
    static func timeLeft(_ book: ShelfBook) -> String? {
        if book.isFinished { return "Finished" }
        if let remaining = book.remaining { return "\(duration(remaining)) left" }
        return book.duration > 0 ? duration(book.duration) : nil
    }
}

// MARK: - Taps

/// What a tap on a book or album does, as the widget is set: plays it in
/// Cue's process (`PlayButton`), opens Cue on the player playing it, opens
/// its page, or nothing of its own (the widget's link). Opening Cue is a
/// `cue://audiobook` or `cue://album` link: a widget's button runs its
/// intent in the extension, an audio intent aside, so one meant to open Cue
/// did nothing.
///
/// The link or button is a clear one over the book, not around it: on iOS
/// 26 one whose label holds an image drawn with
/// `widgetAccentedRenderingMode` (every cover, `BookCover`) opens Cue
/// without its URL, so every book's tap became the widget's own link
/// (developer.apple.com/forums/thread/795408).
struct BookTap<Label: View>: View {
    let book: ShelfBook
    @ViewBuilder let label: Label

    @Environment(\.shelfStyle) private var style

    var body: some View {
        label
            .overlay {
                switch style.action {
                case .play where style.playsInBackground:
                    PlayButton(id: book.id) {
                        Self.target
                    }
                    .accessibilityLabel("Play \(book.title)")
                case .play:
                    Link(destination: style.link(to: book.id, play: true)) {
                        Self.target
                    }
                    .accessibilityLabel("Play \(book.title)")
                case .open:
                    Link(destination: style.link(to: book.id, play: false)) {
                        Self.target
                    }
                    .accessibilityLabel(book.title)
                case .openApp:
                    EmptyView()
                }
            }
    }

    /// The book's whole area, clear, to be tapped.
    private static var target: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(.rect)
    }
}

/// Plays or pauses a book or album in Cue's process, as the widget is:
/// `PlayBookIntent` or `PlayAlbumIntent`, audio intents, which the system
/// runs in Cue rather than the extension.
struct PlayButton<Label: View>: View {
    let id: String
    @ViewBuilder let label: Label

    @Environment(\.shelfStyle) private var style

    var body: some View {
        switch style.kind {
        case .books:
            Button(intent: PlayBookIntent(bookID: id)) {
                label
            }
            .buttonStyle(.plain)
        case .albums:
            Button(intent: PlayAlbumIntent(albumID: id)) {
                label
            }
            .buttonStyle(.plain)
        }
    }
}

/// Play as a capsule, Pause while it plays: for a book what's left of it
/// beside the glyph ("5h 3m left", narrowed to "5h 3m" where that doesn't
/// fit), for an album the word. In Cue's process, or opening Cue to play
/// it, as the widget is set.
struct PlayPauseCapsule: View {
    let book: ShelfBook
    let isPlaying: Bool
    var isRoomy = true

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let left = timeLeft
        content(left)
            .playPauseTarget(book: book, in: Capsule(), label: [isPlaying ? "Pause" : "Play", left?.full].compactMap(\.self).joined(separator: ", "))
    }

    private func content(_ left: (full: String, short: String?)?) -> some View {
        let text = renderingMode == .fullColor ? style.look.palette.text : Color.primary
        return HStack(spacing: 6) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
            if let left {
                ViewThatFits(in: .horizontal) {
                    Text(left.full)
                    if let short = left.short {
                        Text(short)
                    }
                }
                .contentTransition(.numericText())
                .monospacedDigit()
            } else {
                Text(isPlaying ? "Pause" : "Play")
                    .contentTransition(.interpolate)
            }
        }
        .font(.system(isRoomy ? .callout : .subheadline, design: .rounded, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(text)
        .padding(.horizontal, isRoomy ? 16 : 13)
        .frame(minHeight: isRoomy ? 36 : 30)
        // Light on a see-through capsule, as Apple's Music widget draws its
        // Play: where only opacity is kept (a tinted or clear Home Screen),
        // the words still stand out from the capsule.
        .background(text.opacity(0.18), in: .capsule)
        .widgetAccentable()
        // Dimmed from a tap until Cue's write after it lands.
        .invalidatableContent()
    }

    /// What's left of a book, and that without "left"; nil for an album
    /// and a book finished, whose capsule says Play or Pause.
    private var timeLeft: (full: String, short: String?)? {
        guard style.kind == .books, !book.isFinished, let left = BookShelfFormat.timeLeft(book) else { return nil }
        return (left, book.remaining.map(BookShelfFormat.duration))
    }
}

extension View {
    /// Plays or pauses `book` from a clear `shape` laid over the view, as a
    /// book's cover is (`BookTap`): with the glyph, its symbol transition
    /// and its pending dimming as a button's own label, a tap on it ran
    /// nothing.
    func playPauseTarget(book: ShelfBook, in shape: some Shape, label: String) -> some View {
        modifier(PlayPauseTarget(book: book, shape: shape, label: label))
    }
}

private struct PlayPauseTarget<Target: Shape>: ViewModifier {
    let book: ShelfBook
    let shape: Target
    let label: String

    @Environment(\.shelfStyle) private var style

    func body(content: Content) -> some View {
        content
            .overlay {
                if style.playsInBackground {
                    PlayButton(id: book.id) {
                        target
                    }
                    .accessibilityLabel(label)
                } else {
                    Link(destination: style.link(to: book.id, play: true)) {
                        target
                    }
                    .accessibilityLabel(label)
                }
            }
    }

    private var target: some View {
        shape
            .fill(.clear)
            .contentShape(shape)
    }
}

/// Cue's glyph, in the widget's top corner, as Apple's own widgets carry
/// theirs: in Cue's green, or the Home Screen's tint.
struct CueGlyph: View {
    /// What a corner it's in keeps clear of other things.
    static let room: CGFloat = 26

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Image("cue.icon")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .foregroundStyle(renderingMode == .fullColor ? Color("Accent") : Color.primary)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}
