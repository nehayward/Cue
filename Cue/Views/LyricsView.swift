import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
import VibesDS

/// The song's lyrics in the player, in the artwork's place — for this
/// device or a speaker alike, read through `PlaybackRoute.presented`.
///
/// Timed lyrics follow the song: the line being sung bright and filling as
/// it's sung, the rest dim, scrolled to keep it near the top, and a tap on
/// a line plays from there. Scrolling by hand stops the following and
/// brings up Back to Now, which (like a tap on a line) starts it again.
/// Plain lyrics just scroll.
///
/// What it shows is `LyricsService.state`, which the player keeps asking
/// for the song on screen (`LyricsRequestModifier`). Debug builds badge the
/// top corner with where the lyrics came from.
struct LyricsView: View {
    var style: LyricsStyle = .inline
    /// A finger on the lyrics — a scroll, a tap on a line — for the
    /// full-screen player to bring its controls back.
    var onInteraction: () -> Void = {}

    private var service: LyricsService { .shared }

    var body: some View {
        ZStack {
            switch service.state {
            case .loaded(let lyrics) where lyrics.isInstrumental:
                ContentUnavailableView("Instrumental", systemImage: "music.note")
            case .loaded(let lyrics) where lyrics.isSynced:
                // A view per song, so the next song's lyrics open on their
                // own line rather than at this one's scroll position.
                SyncedLyricsView(lyrics: lyrics, style: style, onInteraction: onInteraction)
                    .id(service.key)
            case .loaded(let lyrics):
                PlainLyricsView(lyrics: lyrics, style: style, onInteraction: onInteraction)
                    .id(service.key)
            case .loading:
                // Only once a lookup has taken a moment: from the cache the
                // lyrics are there before it would show.
                ProgressView()
                    .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.4)), removal: .opacity))
            case .failed:
                ContentUnavailableView {
                    Label("Lyrics Couldn't Load", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("Try Again") {
                        let controller = PlaybackRoute.shared.presented
                        service.retry(for: LyricsService.song(of: controller), duration: controller.duration)
                    }
                    .buttonStyle(.bordered)
                }
            case .none, .unavailable:
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: service.state)
#if DEBUG
        .overlay(alignment: .topTrailing) { LyricsDebugBadge() }
#endif
    }
}

/// How big the lyrics are drawn: in the cover's place, or filling the
/// phone's player the way Apple Music does.
struct LyricsStyle {
    var font: Font
    var plainFont: Font
    var spacing: CGFloat
    /// Where the line being sung is kept.
    var anchor: UnitPoint

    static let inline = LyricsStyle(font: .title2.bold(), plainFont: .title3.bold(), spacing: 20, anchor: UnitPoint(x: 0.5, y: 0.3))
    static let fullScreen = LyricsStyle(font: .largeTitle.bold(), plainFont: .title2.bold(), spacing: 26, anchor: UnitPoint(x: 0.5, y: 0.22))
}

// MARK: - Timed

/// The clock the lines follow, a little ahead: read through the route at
/// the moment it's asked, so a line drawn before a hand-off still reads
/// what's heard.
private struct LyricsClock: Equatable {
    let isRunning: Bool
    /// Seconds ahead of the clock the lines are shown. Only while it runs:
    /// the lead makes up for sound still on its way, and there's none while
    /// paused — with it, a paused song showed the line after the one it
    /// stopped on.
    let lead: TimeInterval

    /// On this device the lines light up a moment early, so the eye is on
    /// a line as it's sung.
    static let deviceLead: TimeInterval = 0.15
    /// A speaker's clock runs from whole-second reports that arrive a round
    /// trip late, so it trails the audio; this lead, tuned by ear on Sonos
    /// (Clic uses the same), puts the line on the vocal.
    static let speakerLead: TimeInterval = 0.875

    @MainActor
    init(_ controller: any PlaybackController) {
        isRunning = controller.isClockRunning
        lead = !isRunning ? 0 : controller.group == nil ? Self.deviceLead : Self.speakerLead
    }

    @MainActor
    func position(at date: Date = .now) -> TimeInterval {
        PlaybackRoute.shared.presented.position(at: date) + lead
    }
}

/// The lines, drawn again when the line being sung changes: at the moment
/// the next one starts, rather than on a clock ticking in between.
private struct SyncedLyricsView: View {
    let lyrics: Lyrics
    let style: LyricsStyle
    let onInteraction: () -> Void

    var body: some View {
        let route = PlaybackRoute.shared
        let clock = LyricsClock(route.presented)
        TimelineView(LineStarts(lyrics: lyrics, clock: clock)) { context in
            LyricsLines(
                lyrics: lyrics,
                style: style,
                current: lyrics.lineIndex(at: clock.position(at: context.date)),
                clock: clock,
                canSeek: route.presented.isActive && !route.isHolding,
                onInteraction: onInteraction
            )
        }
    }
}

/// When each line still to come starts, on the clock as it runs now. Made
/// in `SyncedLyricsView`'s body, so a seek or a speaker's correction, which
/// moves the clock, makes it again.
private struct LineStarts: TimelineSchedule {
    let dates: [Date]

    @MainActor
    init(lyrics: Lyrics, clock: LyricsClock) {
        guard clock.isRunning else {
            dates = []
            return
        }
        let now = Date.now
        let position = clock.position(at: now)
        // A millisecond in, so rounding never reads the line before.
        dates = lyrics.lines.compactMap { line in
            line.start.flatMap { $0 > position ? now + ($0 - position + 0.001) : nil }
        }
    }

    func entries(from start: Date, mode: TimelineScheduleMode) -> [Date] {
        [start] + dates.filter { $0 > start }
    }
}

/// The timed lines, following the song.
///
/// A finger scrolling them stops the following and brings up Back to Now,
/// which glides back to the line being sung; that, or a tap on a line,
/// starts the following again. A fling still moving the lyrics would carry
/// on over a glide, so it's stopped where it is first. Nothing that
/// resizes the lyrics starts with a glide — a resize cuts it short — so
/// the full-screen controls only come back once a tapped line has landed.
/// And every glide is checked once it should have landed: if the line
/// being sung isn't on screen by then, it's jumped to.
///
/// A line is drawn again only when it changes (`LyricLineRow` is
/// `Equatable`): on a new line, the one before and the one now. Not lazy:
/// a `LazyVStack` was a third cheaper a frame on an iPhone SE, but a glide
/// across lines it hadn't built yet (Back to Now from the top) was aimed by
/// estimated heights and corrected as they were built, so the lines ran
/// past, back and on again.
private struct LyricsLines: View {
    let lyrics: Lyrics
    let style: LyricsStyle
    let current: Int?
    let clock: LyricsClock
    let canSeek: Bool
    let onInteraction: () -> Void

    /// How long a glide is given to land before it's checked.
    private static let landing: Duration = .milliseconds(650)

    @State private var position = ScrollPosition(idType: Int.self)
    /// Following the song: off once a finger scrolls the lyrics, on again
    /// with Back to Now or a tap on a line.
    @State private var isFollowing = true
    /// A finger, or the fling it left, is still moving the lyrics.
    @State private var isScrolling = false
    /// The lines at least half on screen.
    @State private var visibleLines: Set<Int> = []
    @State private var landingCheck: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: style.spacing) {
                ForEach(lyrics.lines) { line in
                    LyricLineRow(
                        line: line,
                        nextStart: lyrics.nextStart(after: line.id),
                        isCurrent: line.id == current,
                        font: style.font,
                        clock: clock,
                        canSeek: canSeek
                    ) { start in
                        follow(to: line.id, then: onInteraction)
                        Task { await PlaybackRoute.shared.presented.seek(to: start) }
                    }
                    .equatable()
                }
                LyricsCredit(lyrics: lyrics)
            }
            .scrollTargetLayout()
            .padding(.horizontal, 4)
        }
        .scrollPosition($position)
        .lyricsScrollStyle(bottomMargin: 200)
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { visibleLines = Set($0) }
        .onScrollPhaseChange { _, phase in
            // Not `.tracking`: that's any touch, a tap on a line too.
            if phase == .interacting {
                isFollowing = false
                landingCheck?.cancel()
                onInteraction()
            }
            isScrolling = phase == .interacting || phase == .decelerating
        }
        .overlay(alignment: .bottom) {
            backToNow
                .animation(.smooth(duration: 0.25), value: isFollowing)
        }
        // Opens on the line being sung, then glides to each one after.
        .onChange(of: current, initial: true) { old, current in
            guard let current, isFollowing else { return }
            scroll(to: current, glides: old != current)
        }
        .onDisappear { landingCheck?.cancel() }
    }

    @ViewBuilder
    private var backToNow: some View {
        if !isFollowing {
            Button("Back to Now", systemImage: "text.line.first.and.arrowtriangle.forward") {
                follow(to: current ?? lyrics.lines.first?.id ?? 0)
            }
            .font(.subheadline.bold())
#if os(visionOS)
            .buttonStyle(.bordered)
#else
            .buttonStyle(.glass)
#endif
            .buttonBorderShape(.capsule)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// Back to following, gliding to `id`; `then` once it's there.
    private func follow(to id: Int, then: (() -> Void)? = nil) {
        HapticManager.shared.fireHaptic(.selection)
        isFollowing = true
        scroll(to: id, then: then)
    }

    /// Puts line `id` at the style's anchor, gliding unless told not to.
    private func scroll(to id: Int, glides: Bool = true, then: (() -> Void)? = nil) {
        defer { checkLanding(on: id) }
        guard glides else { return jump(to: id) }
        guard isScrolling, let top = visibleLines.min() else { return glide(to: id, then: then) }
        // A fling still running would carry on over the glide: stop it
        // where it is — at most half a line's shift — and glide from there.
        jump(to: top, anchor: .top)
        Task { glide(to: id, then: then) }
    }

    private func glide(to id: Int, then: (() -> Void)?) {
        withAnimation(.smooth(duration: 0.45)) {
            position.scrollTo(id: id, anchor: style.anchor)
        } completion: {
            then?()
        }
    }

    private func jump(to id: Int, anchor: UnitPoint? = nil) {
        withTransaction(\.disablesAnimations, true) {
            position.scrollTo(id: id, anchor: anchor ?? style.anchor)
        }
    }

    /// Once the scroll should have landed, the line is on screen, or it's
    /// jumped to — unless a finger has taken over since.
    private func checkLanding(on id: Int) {
        landingCheck?.cancel()
        landingCheck = Task {
            try? await Task.sleep(for: Self.landing)
            guard !Task.isCancelled, isFollowing, !isScrolling, !visibleLines.contains(id) else { return }
            jump(to: id)
        }
    }
}

private struct LyricLineRow: View, Equatable {
    let line: Lyrics.Line
    let nextStart: TimeInterval?
    let isCurrent: Bool
    let font: Font
    let clock: LyricsClock
    let canSeek: Bool
    let onTap: (TimeInterval) -> Void

    /// Everything but the tap, which a closure can't be compared on.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line && lhs.nextStart == rhs.nextStart && lhs.isCurrent == rhs.isCurrent
            && lhs.font == rhs.font && lhs.clock == rhs.clock && lhs.canSeek == rhs.canSeek
    }

    var body: some View {
        Button {
            if let start = line.start { onTap(start) }
        } label: {
            text
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSeek || line.start == nil)
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private var text: some View {
        if line.isBreak {
            Text("• • •")
                .foregroundStyle(isCurrent ? .primary : .tertiary)
                .accessibilityLabel("Instrumental")
        } else if isCurrent {
            // Filled through as it's sung: by its words when they're timed,
            // at a singing pace when only the line is.
#if targetEnvironment(macCatalyst)
            LyricFill(line: line, nextStart: nextStart, clock: clock)
#else
            // Drawn over a hidden copy that holds its place, so a frame's
            // fill redraws the line alone: as the line itself, each frame's
            // renderer had the text measured again and every line laid out,
            // scrolled and checked for visibility — two fifths of the main
            // thread on an iPhone SE.
            Text(line.text)
                .hidden()
                .overlay(alignment: .topLeading) {
                    PlaybackTimeline(isRunning: clock.isRunning, minimumInterval: 1.0 / 60, position: { clock.position() }) { position in
                        Text(line.text)
                            .textRenderer(LyricFillRenderer(progress: line.progress(at: position, nextStart: nextStart)))
                    }
                }
#endif
        } else {
            Text(line.text)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Draws a line of lyrics bright up to how much has been sung and dim after,
/// row by row of the wrapped text — so a line that wraps fills its first
/// row before its second, the way it's read, and right to left for Arabic
/// or Hebrew — with a soft front edge. `progress` is a fraction of the
/// characters, taken as glyphs.
///
/// Drawn every frame, so a row before the front is drawn once bright, a row
/// after it once dim, and only the front's row is measured glyph by glyph.
private struct LyricFillRenderer: TextRenderer {
    var progress: Double
    /// What's still to come, matching the other lines' `.tertiary`.
    var dimOpacity: Double = 0.32
    /// How wide the fading front of the fill is.
    var feather: CGFloat = 22
    /// The front fades out in steps of clips and opacity — no layers or
    /// blend modes, so it's cheap enough to draw every frame.
    var featherSteps = 6

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let total = layout.reduce(0) { $0 + Self.glyphs(in: $1) }
        var sung = max(0, min(1, progress)) * Double(total)
        for row in layout {
            let glyphs = Double(Self.glyphs(in: row))
            if sung >= glyphs {
                ctx.draw(row)
                sung -= glyphs
                continue
            }
            var dim = ctx
            dim.opacity = dimOpacity
            dim.draw(row)
            if sung > 0 {
                drawFront(of: row, sung: sung, in: ctx)
                sung = 0
            }
        }
    }

    private static func glyphs(in row: Text.Layout.Line) -> Int {
        row.reduce(0) { $0 + $1.count }
    }

    /// The row the front is in: bright up to `sung` glyphs, fading out
    /// across the feather before it.
    private func drawFront(of row: Text.Layout.Line, sung: Double, in ctx: GraphicsContext) {
        guard let front = frontEdge(in: glyphSpans(of: row), sung: sung) else { return }
        let bounds = row.typographicBounds.rect
        let isRightToLeft = row.isRightToLeft
        let solidEnd = max(0, front - feather)

        // Tall enough for accents and descenders past the type's bounds.
        let band = bounds.insetBy(dx: -2, dy: -bounds.height * 0.3)
        func clip(from start: CGFloat, to end: CGFloat) -> Path {
            let x = isRightToLeft ? bounds.maxX - end : bounds.minX + start
            return Path(CGRect(x: x, y: band.minY, width: end - start, height: band.height))
        }
        if solidEnd > 0 {
            var lit = ctx
            lit.clip(to: clip(from: -2, to: solidEnd))
            lit.draw(row)
        }
        let step = (front - solidEnd) / CGFloat(featherSteps)
        for index in 0..<featherSteps {
            var lit = ctx
            lit.opacity = 1 - (Double(index) + 0.5) / Double(featherSteps)
            let start = solidEnd + step * CGFloat(index)
            lit.clip(to: clip(from: start, to: start + step))
            lit.draw(row)
        }
    }
}

private extension Text.Layout.Line {
    var isRightToLeft: Bool { first?.layoutDirection == .rightToLeft }
}

/// Each glyph's span along a row of a wrapped line, in order, measured the
/// way the row reads: from its left edge for left-to-right text, from its
/// right for Arabic or Hebrew.
private func glyphSpans(of row: Text.Layout.Line) -> [ClosedRange<CGFloat>] {
    let bounds = row.typographicBounds.rect
    return row.flatMap { $0 }
        .map { slice -> ClosedRange<CGFloat> in
            let glyph = slice.typographicBounds.rect
            return row.isRightToLeft
                ? (bounds.maxX - glyph.maxX)...(bounds.maxX - glyph.minX)
                : (glyph.minX - bounds.minX)...(glyph.maxX - bounds.minX)
        }
        .sorted { $0.lowerBound < $1.lowerBound }
}

/// How far along a row the fill's front is, `sung` glyphs in; `nil` past
/// its last.
private func frontEdge(in spans: [ClosedRange<CGFloat>], sung: Double) -> CGFloat? {
    let whole = Int(sung)
    guard spans.indices.contains(whole) else { return nil }
    let span = spans[whole]
    return span.lowerBound + (span.upperBound - span.lowerBound) * (sung - Double(whole))
}

#if targetEnvironment(macCatalyst)
/// The line being sung on the Mac: drawn twice, dim and bright, with the
/// bright copy showing through a bar per row that slides as the line is
/// sung, so a frame moves the bars and draws no text. Text drawn again every
/// frame (`LyricFillRenderer`) runs SwiftUI's GPU renderer on the Mac,
/// holding ~90 MB of GPU memory while a line fills; on an iPhone SE the mask
/// cost the render server two fifths more than the renderer, so it's the
/// Mac's alone. The rows come from the dim copy's layout (`Text.LayoutKey`).
private struct LyricFill: View {
    let line: Lyrics.Line
    let nextStart: TimeInterval?
    let clock: LyricsClock

    var body: some View {
        Text(line.text)
            .foregroundStyle(.tertiary)
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    let rows = layouts.first.map { FillRow.rows(of: $0.layout, at: proxy[$0.origin]) } ?? []
                    Text(line.text)
                        .mask(alignment: .topLeading) {
                            PlaybackTimeline(isRunning: clock.isRunning, minimumInterval: 1.0 / 60, position: { clock.position() }) { position in
                                FillBars(rows: rows, progress: line.progress(at: position, nextStart: nextStart))
                            }
                        }
                        .accessibilityHidden(true)
                }
            }
    }
}

/// A row of the line being sung, as the Mac's fill needs it.
private struct FillRow {
    /// The row's strip of the line: its type's bounds, out to halfway to
    /// the rows beside it (and a little past the first and last, for
    /// accents and descenders), so one row's bar never shows another's.
    var band: CGRect
    var isRightToLeft: Bool
    var spans: [ClosedRange<CGFloat>]

    static func rows(of layout: Text.Layout, at origin: CGPoint) -> [FillRow] {
        let bounds = layout.map { $0.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y) }
        return layout.indices.map { index in
            let rect = bounds[index]
            let top = index == 0 ? rect.minY - rect.height * 0.3 : (bounds[index - 1].maxY + rect.minY) / 2
            let bottom = index == bounds.count - 1 ? rect.maxY + rect.height * 0.3 : (rect.maxY + bounds[index + 1].minY) / 2
            return FillRow(
                band: CGRect(x: rect.minX - 2, y: top, width: rect.width + 4, height: bottom - top),
                isRightToLeft: layout[index].isRightToLeft,
                spans: glyphSpans(of: layout[index])
            )
        }
    }
}

/// The mask over the bright copy: a solid bar per row, its soft front edge
/// at how far the row has been sung.
private struct FillBars: View {
    let rows: [FillRow]
    let progress: Double
    /// How wide the fading front of the fill is.
    var feather: CGFloat = 22

    var body: some View {
        let fronts = fronts()
        ZStack(alignment: .topLeading) {
            ForEach(rows.indices, id: \.self) { index in
                bar(rows[index], front: fronts[index])
            }
        }
    }

    /// One row's bar, placed to show the row up to `front` the way it
    /// reads, fading out over the `feather` before it.
    private func bar(_ row: FillRow, front: CGFloat) -> some View {
        let solid = Color.black.frame(width: row.band.width)
        let edge = LinearGradient(
            colors: [.black, .clear],
            startPoint: row.isRightToLeft ? .trailing : .leading,
            endPoint: row.isRightToLeft ? .leading : .trailing
        )
        .frame(width: feather)
        return HStack(spacing: 0) {
            if row.isRightToLeft {
                edge
                solid
            } else {
                solid
                edge
            }
        }
        .frame(height: row.band.height)
        .offset(
            x: row.isRightToLeft ? row.band.maxX - front : row.band.minX - row.band.width - feather + front,
            y: row.band.minY
        )
    }

    /// How far into each row's band the front is: past its end, feather and
    /// all, for a row sung, 0 for one not yet.
    private func fronts() -> [CGFloat] {
        let total = rows.reduce(0) { $0 + $1.spans.count }
        var sung = max(0, min(1, progress)) * Double(total)
        return rows.map { row in
            let glyphs = Double(row.spans.count)
            defer { sung = max(0, sung - glyphs) }
            if sung >= glyphs { return row.band.width + feather }
            guard sung > 0, let front = frontEdge(in: row.spans, sung: sung) else { return 0 }
            // The band starts 2 points before the row.
            return front + 2
        }
    }
}
#endif

// MARK: - Plain

private struct PlainLyricsView: View {
    let lyrics: Lyrics
    let style: LyricsStyle
    let onInteraction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(lyrics.lines.map(\.text).joined(separator: "\n"))
                    .font(style.plainFont)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                LyricsCredit(lyrics: lyrics)
            }
            .padding(.horizontal, 4)
        }
        .lyricsScrollStyle(bottomMargin: 24)
        .onScrollPhaseChange { _, phase in
            // Not `.tracking`: that's any touch.
            if phase == .interacting { onInteraction() }
        }
    }
}

// MARK: - Pieces

private extension View {
    /// The lyrics' scroll view: no indicators, room above the first line and
    /// below the last, and lines fading out at the edges rather than cut.
    func lyricsScrollStyle(bottomMargin: CGFloat) -> some View {
        scrollIndicators(.hidden)
            .contentMargins(.top, 24, for: .scrollContent)
            .contentMargins(.bottom, bottomMargin, for: .scrollContent)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }
}

/// Where the words came from, under the last line.
private struct LyricsCredit: View {
    let lyrics: Lyrics

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: String {
        if let credit = lyrics.credit { return "Lyrics by \(credit)" }
        return switch lyrics.source {
        case .plex: "Lyrics from Plex"
        case .subsonic: "Lyrics from your server"
        case .file: "Lyrics from the file"
        case .lrclib: "Lyrics from LRCLIB"
        }
    }
}

#if DEBUG
/// Where the lyrics on screen came from, how they're timed and whether
/// the cache answered — for checking the sources on a device.
private struct LyricsDebugBadge: View {
    private var service: LyricsService { .shared }

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: .capsule)
            .allowsHitTesting(false)
    }

    private var text: String {
        let origin = service.origin?.rawValue ?? "…"
        switch service.state {
        case .loaded(let lyrics):
            let kind = lyrics.isInstrumental ? "instrumental" : lyrics.isWordTimed ? "word-timed" : lyrics.isSynced ? "timed" : "plain"
            let credit = lyrics.credit.map { " (\($0))" } ?? ""
            return "\(lyrics.source.rawValue)\(credit) · \(kind) · \(lyrics.lines.count) lines · \(origin)"
        case .none:
            return "none · \(service.isOnlineLookupEnabled ? "service + lrclib" : "service only") · \(origin)"
        case .loading: return "loading"
        case .failed: return "failed"
        case .unavailable: return "unavailable"
        }
    }
}
#endif

/// Beside the cover's thumbnail at the top of the phone's full-screen
/// lyrics: the title and the artist — a tap goes back to the cover — and
/// the switch that puts the controls away (or brings them back) at once,
/// rather than waiting for them to go by themselves.
struct LyricsHeaderTitles: View {
    let item: PlayableContent?
    /// The controls are away.
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    let onShowCover: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onShowCover) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item?.title ?? "Not Playing")
                        .font(.headline)
                    Text(item.map { $0.metadata?.artist ?? $0.subtitle } ?? " ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityHint("Shows the cover")

            Button(action: onToggleFullScreen) {
                Label(
                    isFullScreen ? "Show Controls" : "Full Screen",
                    systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                )
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Keeps `LyricsService` asking for the song on screen while the player is
/// open, so the lyrics button knows whether there are any before it's
/// tapped. Asked again when the song's length arrives, which a speaker
/// sends a moment after the song changes.
struct LyricsRequestModifier: ViewModifier {
    @AppStorage(AppStorageKeys.lyricsShown) private var isShown: Bool = false

    private struct Request: Equatable {
        let key: String?
        let hasDuration: Bool
    }

    func body(content: Content) -> some View {
        let controller = PlaybackRoute.shared.presented
        let song = LyricsService.song(of: controller)
        // While lyrics are on, the next song's are looked up a few seconds
        // into this one's, so they're there when it starts. This device's
        // queue only: a speaker's next song arrives under another id than
        // the one it plays with.
        let next = isShown && controller.group == nil ? Self.nextSong() : nil
        content
            .task(id: Request(key: song.map(LyricsService.key(for:)), hasDuration: controller.duration > 0)) {
                LyricsService.shared.request(for: song, duration: controller.duration)
            }
            .task(id: next.map(LyricsService.key(for:))) {
                guard let next, (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                LyricsService.shared.prefetch(next, duration: next.metadata?.duration.map { $0 / .seconds(1) } ?? 0)
            }
    }

    /// The song after this device's current one, when it can have lyrics.
    private static func nextSong() -> PlayableContent? {
        let playback = LocalPlaybackService.shared
        let index = playback.currentIndex + 1
        guard playback.queue.indices.contains(index) else { return nil }
        let item = playback.queue[index]
        guard !item.content.type.isRadio, item.metadata?.radioStation != true else { return nil }
        return item
    }
}

/// The player's switch for lyrics in the artwork's place. Dimmed for a
/// song with none, and for a station — unless lyrics are on, so they can
/// still be turned off while the cover stands in. The player animates the
/// switch (`PlayerView`).
struct LyricsButton: View {
    @AppStorage(AppStorageKeys.lyricsShown) private var isShown: Bool = false

    private var isAvailable: Bool {
        switch LyricsService.shared.state {
        case .loaded, .loading, .failed: true
        case .none, .unavailable: false
        }
    }

    var body: some View {
        Button("Lyrics", systemImage: isShown ? "quote.bubble.fill" : "quote.bubble") {
            HapticManager.shared.fireHaptic(.selection)
            isShown.toggle()
        }
        .labelStyle(.iconOnly)
#if targetEnvironment(macCatalyst)
        // An animated symbol swap costs the Mac ~90 MB of GPU memory.
        .contentTransition(.identity)
#else
        .contentTransition(.symbolEffect(.replace))
#endif
        .disabled(!isAvailable && !isShown)
        .help("Lyrics")
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}
