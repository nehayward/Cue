import Defaults
import SwiftUI
import UIKit
import WidgetKit

typealias ShelfBook = BookShelfWidgetState.Book

// MARK: - Style

/// The widget's settings, for the views deep in it.
struct ShelfStyle {
    var look: BookShelfLook = .bookshelf
    var action: BookWidgetAction = .playBook
    var playsInBackground = true
    var showsProgress = true

    init() {}

    init(_ configuration: BookShelfConfigurationIntent) {
        look = configuration.look
        action = configuration.action
        playsInBackground = configuration.playsInBackground
        showsProgress = configuration.showsProgress
    }
}

extension EnvironmentValues {
    @Entry var shelfStyle: ShelfStyle = ShelfStyle()
}

extension BookShelfLook {
    /// How much wider than its cover a book stands on the shelf: a record's
    /// disc shows past its sleeve.
    var footprint: CGFloat {
        self == .records ? 1.3 : 1
    }

    /// The room between two books on a shelf.
    var gap: CGFloat {
        self == .records ? 8 : 12
    }

    var palette: ShelfPalette {
        self == .records ? .ebony : .walnut
    }
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
}

// MARK: - Background

/// The wall behind the shelves: the look's wood, its grain, and darker at
/// the edges.
struct ShelfBackground: View {
    let look: BookShelfLook

    var body: some View {
        let palette = look.palette
        ZStack {
            LinearGradient(colors: [palette.backTop, palette.backBottom], startPoint: .top, endPoint: .bottom)
            WoodGrain(look: look)
            RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center, startRadius: 60, endRadius: 420)
        }
    }
}

/// Fine streaks running across the wall, the same every time for a look.
private struct WoodGrain: View {
    let look: BookShelfLook

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
/// edge, and its shadow on the wall below. On a tinted Home Screen, a line.
struct ShelfPlank: View {
    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    static let height: CGFloat = 12
    /// How far the books stand into its top.
    static let standing: CGFloat = 3

    var body: some View {
        if renderingMode == .fullColor {
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
                    BookOnShelf(book: book, side: side, isPlaying: state.isPlaying(book))
                }
            }
        }
    }
}

// MARK: - A book

/// A book as it stands on the shelf: a hardcover with its spine catching
/// the light, or a record sleeve with its record slid out, how far in along
/// its foot.
struct BookOnShelf: View {
    let book: ShelfBook
    let side: CGFloat
    let isPlaying: Bool

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
                    CoverProgress(book: book, side: side)
                }
            }
            .overlay(alignment: .topLeading) {
                if isPlaying {
                    PlayingBadge(size: max(side * 0.2, 16))
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
        .frame(width: side * BookShelfLook.records.footprint, height: side, alignment: .leading)
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

    var body: some View {
        Color.clear
            .overlay {
                if let name = book.cover, let image = BookCoverImages.image(named: name) {
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

enum BookCoverImages {
    static func image(named name: String) -> UIImage? {
        guard let url = BookShelfWidgetState.coverURL(named: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// A cloth cover with the title stamped on it, for a book with no cover of
/// its own and the gallery's made-up books. Its colour comes from the
/// title, so a book keeps it.
struct GeneratedCover: View {
    let title: String
    let author: String

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
                            .font(.system(size: side * 0.13, weight: .semibold, design: .serif))
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
        } else if let fraction = book.fraction {
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
    let isPlaying: Bool

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
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .frame(width: 15, height: 15)
            Text(BookShelfFormat.percent(fraction))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.45), in: .capsule)
    }
}

/// A playing book's mark: a waveform in a dark circle.
struct PlayingBadge: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.black.opacity(0.55), in: .circle)
            .widgetAccentable()
            .accessibilityLabel("Playing")
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

/// What a tap on a book does, as the widget is set: plays it (in Cue's
/// process, or opening Cue), opens its page, or nothing of its own (the
/// widget's link, the Audiobooks tab).
struct BookTap<Label: View>: View {
    let book: ShelfBook
    @ViewBuilder let label: Label

    @Environment(\.shelfStyle) private var style

    var body: some View {
        switch style.action {
        case .playBook where style.playsInBackground:
            Button(intent: PlayBookIntent(bookID: book.id)) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(book.title)")
        case .playBook:
            Link(destination: BookShelfWidgetState.link(to: book.id, play: true)) {
                label
            }
            .accessibilityLabel("Play \(book.title)")
        case .openBook:
            Link(destination: BookShelfWidgetState.link(to: book.id, play: false)) {
                label
            }
            .accessibilityLabel(book.title)
        case .openApp:
            label
        }
    }
}

/// A round Play, Pause while the book plays: in Cue's process, or opening
/// Cue to play it, as the widget is set.
struct PlayPauseButton: View {
    let book: ShelfBook
    let isPlaying: Bool
    let size: CGFloat

    @Environment(\.shelfStyle) private var style
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if style.playsInBackground {
            Button(intent: PlayBookIntent(bookID: book.id)) {
                glyph
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        } else {
            Link(destination: BookShelfWidgetState.link(to: book.id, play: true)) {
                glyph
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
    }

    private var glyph: some View {
        let palette = style.look.palette
        let isFullColor = renderingMode == .fullColor
        return Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(isFullColor ? palette.backBottom : Color.black)
            // The play triangle sits a touch right of centre to look centred.
            .offset(x: isPlaying ? 0 : size * 0.04)
            .frame(width: size, height: size)
            .background(isFullColor ? palette.text : Color.white, in: .circle)
            .widgetAccentable()
    }
}
