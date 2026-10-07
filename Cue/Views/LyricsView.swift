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
/// a line plays from there. Scrolling by hand stops the following and brings up
/// Back to Now, which (like a tap on a line) starts it again. Plain lyrics
/// just scroll.
///
/// Debug builds badge the top corner with where the lyrics came from.
///
/// What it shows is `LyricsService.state`, which the player keeps asking
/// for the song on screen (`LyricsRequestModifier`).
struct LyricsView: View {
    var style: LyricsStyle = .inline
    /// A finger on the lyrics — a scroll, a tap on a line — for the
    /// full-screen player to bring its controls back.
    var onInteraction: () -> Void = {}

    private var service: LyricsService { .shared }
    private var route: PlaybackRoute { .shared }

    var body: some View {
        Group {
            switch service.state {
            case .loaded(let lyrics) where lyrics.isInstrumental:
                message("Instrumental", systemImage: "music.note")
            case .loaded(let lyrics) where lyrics.isSynced:
                // A view per song: the next one's lyrics can come straight
                // from the cache, and would otherwise open at the last
                // one's scroll position.
                SyncedLyricsView(lyrics: lyrics, songKey: service.key ?? "", style: style, onInteraction: onInteraction)
                    .id(service.key)
            case .loaded(let lyrics):
                PlainLyricsView(lyrics: lyrics, style: style, onInteraction: onInteraction)
                    .id(service.key)
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                VStack(spacing: 12) {
                    messageContent("Lyrics couldn't be loaded.", systemImage: "wifi.exclamationmark")
                    Button("Try Again") {
                        let controller = route.presented
                        service.retry(for: LyricsService.song(of: controller), duration: controller.duration)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .none, .unavailable:
                message("No Lyrics", systemImage: "quote.bubble")
            }
        }
        .transition(.opacity)
#if DEBUG
        .overlay(alignment: .topTrailing) {
            LyricsDebugBadge()
        }
#endif
    }

    private func message(_ text: String, systemImage: String) -> some View {
        messageContent(text, systemImage: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageContent(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// How big the lyrics are drawn: in the cover's place, or filling the
/// phone's player the way Apple Music does.
struct LyricsStyle: Equatable {
    var font: Font
    var plainFont: Font
    var spacing: CGFloat
    /// Where the line being sung is kept.
    var anchor: UnitPoint

    static let inline = LyricsStyle(font: .title2.bold(), plainFont: .title3.bold(), spacing: 20, anchor: UnitPoint(x: 0.5, y: 0.3))
    static let fullScreen = LyricsStyle(font: .largeTitle.bold(), plainFont: .title2.bold(), spacing: 26, anchor: UnitPoint(x: 0.5, y: 0.22))
}

// MARK: - Timed

/// The clock the lines follow, read through the route at the moment it's
/// asked, so a line drawn before a hand-off still reads what's heard.
private struct LyricsClock {
    let isRunning: Bool

    @MainActor
    func position() -> TimeInterval {
        PlaybackRoute.shared.presented.position()
    }
}

private struct SyncedLyricsView: View {
    let lyrics: Lyrics
    let songKey: String
    let style: LyricsStyle
    let onInteraction: () -> Void

    private var route: PlaybackRoute { .shared }

    /// Lines light up a moment early, so the eye is on a line as it's sung.
    static let deviceLead: TimeInterval = 0.15
    /// A speaker's clock runs from whole-second reports that arrive a round
    /// trip late, so it trails the audio; this lead, tuned by ear on Sonos
    /// (Clic uses the same), puts the line on the vocal.
    static let speakerLead: TimeInterval = 0.875

    var body: some View {
        let controller = route.presented
        let clock = LyricsClock(isRunning: controller.isClockRunning)
        // Only while the clock runs: the lead makes up for sound still on
        // its way, and there's none while paused — with it, a paused song
        // showed the line after the one it stopped on.
        let lead = !clock.isRunning ? 0 : controller.group == nil ? Self.deviceLead : Self.speakerLead
        PlaybackTimeline(
            isRunning: clock.isRunning,
            minimumInterval: 0.1,
            position: clock.position
        ) { position in
            let input = LyricsLinesInput(
                lyrics: lyrics,
                songKey: songKey,
                style: style,
                current: lyrics.lineIndex(at: position + lead),
                lead: lead,
                clock: clock,
                canSeek: controller.isActive && !route.isHolding,
                seek: { start in
                    HapticManager.shared.fireHaptic(.selection)
                    Task { await PlaybackRoute.shared.presented.seek(to: start) }
                },
                onInteraction: onInteraction
            )
            if #available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *) {
                LyricsLines(input: input)
                    .equatable()
            } else {
                LegacyLyricsLines(input: input)
                    .equatable()
            }
        }
    }
}

/// What the lines are drawn from. Equal when drawing again would draw the
/// same — the clock above ticks ten times a second, and most ticks land on
/// the same line, so the lines are only drawn again when it changes. The
/// line being sung runs a clock of its own to fill as it's sung.
private struct LyricsLinesInput: Equatable {
    let lyrics: Lyrics
    let songKey: String
    let style: LyricsStyle
    let current: Int?
    /// Seconds ahead of the clock the lines are shown.
    let lead: TimeInterval
    let clock: LyricsClock
    let canSeek: Bool
    let seek: (TimeInterval) -> Void
    let onInteraction: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.songKey == rhs.songKey && lhs.current == rhs.current && lhs.canSeek == rhs.canSeek
            && lhs.style == rhs.style && lhs.clock.isRunning == rhs.clock.isRunning && lhs.lead == rhs.lead
    }

    func row(_ line: Lyrics.Line, onTap: @escaping (TimeInterval) -> Void) -> LyricLineRow {
        LyricLineRow(
            line: line,
            nextStart: lyrics.nextStart(after: line.id),
            isCurrent: line.id == current,
            font: style.font,
            lead: lead,
            clock: clock,
            canSeek: canSeek,
            seek: onTap
        )
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
@available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *)
private struct LyricsLines: View, Equatable {
    let input: LyricsLinesInput

    /// How long a glide is given to land before it's checked.
    private static let landing: Duration = .milliseconds(650)

    @State private var position: ScrollPosition
    /// Following the song: off once a finger scrolls the lyrics, on again
    /// with Back to Now or a tap on a line.
    @State private var isFollowing = true
    /// A finger, or the fling it left, is still moving the lyrics.
    @State private var isScrolling = false
    /// The lines at least half on screen.
    @State private var visibleLines: Set<Int> = []
    @State private var landingCheck: Task<Void, Never>?

    init(input: LyricsLinesInput) {
        self.input = input
        // Open on the line being sung, rather than at the top and then a
        // scroll down to it.
        _position = State(initialValue: input.current.map { ScrollPosition(id: $0, anchor: input.style.anchor) }
            ?? ScrollPosition(idType: Int.self))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.input == rhs.input
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: input.style.spacing) {
                ForEach(input.lyrics.lines) { line in
                    input.row(line) { start in
                        follow(to: line.id, then: input.onInteraction)
                        input.seek(start)
                    }
                }
                LyricsCredit(lyrics: input.lyrics)
            }
            .scrollTargetLayout()
            .padding(.horizontal, 4)
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 24, for: .scrollContent)
        .contentMargins(.bottom, 200, for: .scrollContent)
        .mask(LyricsFade())
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { ids in
            visibleLines = Set(ids)
        }
        .onScrollPhaseChange { _, phase in
            // Not `.tracking`: that's any touch, a tap on a line too.
            if phase == .interacting {
                isFollowing = false
                landingCheck?.cancel()
                input.onInteraction()
            }
            isScrolling = phase == .interacting || phase == .decelerating
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if !isFollowing {
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        follow(to: input.current ?? input.lyrics.lines.first?.id ?? 0)
                    } label: {
                        Label("Back to Now", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .font(.subheadline.bold())
                    }
                    .modifier(BackToNowStyle())
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.smooth(duration: 0.25), value: isFollowing)
        }
        .onChange(of: input.current) { _, current in
            guard let current, isFollowing else { return }
            scroll(to: current)
        }
        .onChange(of: input.style) {
            guard let current = input.current else { return }
            scroll(to: current, glides: false)
        }
        .onDisappear { landingCheck?.cancel() }
    }

    /// Back to following, gliding to `id`; `then` once it's there.
    private func follow(to id: Int, then: (() -> Void)? = nil) {
        isFollowing = true
        scroll(to: id, then: then)
    }

    /// Puts line `id` at the style's anchor, gliding unless told not to.
    private func scroll(to id: Int, glides: Bool = true, then: (() -> Void)? = nil) {
        defer { checkLanding(on: id) }
        guard glides else {
            jump(to: id)
            then?()
            return
        }
        guard isScrolling, let top = visibleLines.min() else {
            glide(to: id, then: then)
            return
        }
        // A fling still running would carry on over the glide: stop it
        // where it is — at most half a line's shift — and glide from there.
        jump(to: top, anchor: .top)
        Task { @MainActor in
            glide(to: id, then: then)
        }
    }

    private func glide(to id: Int, then: (() -> Void)?) {
        withAnimation(.smooth(duration: 0.45)) {
            position.scrollTo(id: id, anchor: input.style.anchor)
        } completion: {
            then?()
        }
    }

    private func jump(to id: Int, anchor: UnitPoint? = nil) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(id: id, anchor: anchor ?? input.style.anchor)
        }
    }

    /// Once the scroll should have landed, the line is on screen, or it's
    /// jumped to — unless a finger has taken over since.
    private func checkLanding(on id: Int) {
        landingCheck?.cancel()
        landingCheck = Task { @MainActor in
            try? await Task.sleep(for: Self.landing)
            guard !Task.isCancelled, isFollowing, !isScrolling, !visibleLines.contains(id) else { return }
            jump(to: id)
        }
    }
}

/// Before iOS 18: the lines follow the song, with no telling a finger's
/// scroll from the following's, so no Back to Now.
private struct LegacyLyricsLines: View, Equatable {
    let input: LyricsLinesInput

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.input == rhs.input
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: input.style.spacing) {
                    ForEach(input.lyrics.lines) { line in
                        input.row(line) { start in
                            input.onInteraction()
                            input.seek(start)
                        }
                        .id(line.id)
                    }
                    LyricsCredit(lyrics: input.lyrics)
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.top, 24, for: .scrollContent)
            .contentMargins(.bottom, 200, for: .scrollContent)
            .mask(LyricsFade())
            .onAppear {
                if let current = input.current { proxy.scrollTo(current, anchor: input.style.anchor) }
            }
            .onChange(of: input.current) { _, current in
                guard let current else { return }
                withAnimation(.smooth(duration: 0.45)) {
                    proxy.scrollTo(current, anchor: input.style.anchor)
                }
            }
        }
    }
}

/// Glass on iOS 26, a bordered capsule before it.
private struct BackToNowStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(visionOS)
        content.buttonStyle(.bordered).buttonBorderShape(.capsule)
#else
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
#endif
    }
}

private struct LyricLineRow: View {
    let line: Lyrics.Line
    let nextStart: TimeInterval?
    let isCurrent: Bool
    let font: Font
    let lead: TimeInterval
    let clock: LyricsClock
    let canSeek: Bool
    let seek: (TimeInterval) -> Void

    var body: some View {
        Button {
            if let start = line.start { seek(start) }
        } label: {
            label
                .font(font)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.25), value: isCurrent)
        }
        .buttonStyle(.plain)
        .disabled(!canSeek || line.start == nil)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private var label: some View {
        if line.isBreak {
            Text("• • •")
                .foregroundStyle(isCurrent ? .primary : .tertiary)
                .accessibilityLabel("Instrumental")
        } else if isCurrent {
            if #available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *) {
                // Filled through as it's sung: by its words when they're
                // timed, at a singing pace when only the line is.
                PlaybackTimeline(isRunning: clock.isRunning, minimumInterval: 1.0 / 60, position: clock.position) { position in
                    Text(line.text)
                        .textRenderer(LyricFillRenderer(
                            progress: line.progress(at: position + lead, nextStart: nextStart)
                        ))
                }
                .foregroundStyle(.primary)
            } else {
                Text(line.text)
                    .foregroundStyle(.primary)
            }
        } else {
            Text(line.text)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Draws a line of lyrics dim, then bright up to how much has been sung,
/// line by line of the wrapped text — so a line that wraps fills its first
/// row before its second, the way it's read, and right to left for Arabic
/// or Hebrew — with a soft front edge.
/// `progress` is a fraction of the characters, taken as glyphs.
@available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *)
private struct LyricFillRenderer: TextRenderer {
    var progress: Double
    /// What's still to come, matching the other lines' `.tertiary`.
    var dimOpacity: Double = 0.32
    /// How wide the fading front of the fill is.
    var feather: CGFloat = 22

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let glyphs = layout.reduce(0) { total, line in total + line.reduce(0) { $0 + $1.count } }
        var remaining = max(0, min(1, progress)) * Double(glyphs)

        for line in layout {
            var dim = ctx
            dim.opacity = dimOpacity
            dim.draw(line)
            guard remaining > 0 else { continue }

            // Distances are measured the way the line reads: from its left
            // edge for left-to-right text, from its right for Arabic or
            // Hebrew, whose fill runs leftward.
            let bounds = line.typographicBounds.rect
            let isRightToLeft = line.first?.layoutDirection == .rightToLeft
            var spans: [(start: CGFloat, end: CGFloat)] = []
            for run in line {
                for slice in run {
                    let glyph = slice.typographicBounds.rect
                    if isRightToLeft {
                        spans.append((start: bounds.maxX - glyph.maxX, end: bounds.maxX - glyph.minX))
                    } else {
                        spans.append((start: glyph.minX - bounds.minX, end: glyph.maxX - bounds.minX))
                    }
                }
            }
            spans.sort { $0.start < $1.start }
            var front: CGFloat = 0
            var isWhole = true
            for span in spans {
                if remaining >= 1 {
                    front = span.end
                    remaining -= 1
                } else {
                    front = span.start + (span.end - span.start) * remaining
                    remaining = 0
                    isWhole = false
                    break
                }
            }

            // Tall enough for accents and descenders past the type's bounds.
            let band = bounds.insetBy(dx: -2, dy: -bounds.height * 0.3)
            func rect(from start: CGFloat, to end: CGFloat) -> CGRect {
                let x = isRightToLeft ? bounds.maxX - end : bounds.minX + start
                return CGRect(x: x, y: band.minY, width: end - start, height: band.height)
            }
            let solidEnd = isWhole ? front + 2 : max(0, front - feather)
            if solidEnd > 0 {
                var lit = ctx
                lit.clip(to: Path(rect(from: -2, to: solidEnd)))
                lit.draw(line)
            }
            guard !isWhole, front > solidEnd else { continue }
            // The front fades out in steps: clips and opacity, no layers or
            // blend modes, so it's cheap enough to draw every frame.
            let steps = 6
            let step = (front - solidEnd) / CGFloat(steps)
            for index in 0..<steps {
                var lit = ctx
                lit.opacity = 1 - (Double(index) + 0.5) / Double(steps)
                let start = solidEnd + step * CGFloat(index)
                lit.clip(to: Path(rect(from: start, to: start + step)))
                lit.draw(line)
            }
        }
    }
}

/// Tells when a finger scrolls the plain lyrics, for the full-screen
/// player to bring its controls back. Scroll phases are iOS 18.
private struct HandScrollTracking: ViewModifier {
    let onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macCatalyst 18.0, visionOS 2.0, *) {
            content.onScrollPhaseChange { _, phase in
                // Not `.tracking`: that's any touch.
                if phase == .interacting {
                    onScroll()
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Plain

private struct PlainLyricsView: View {
    let lyrics: Lyrics
    let style: LyricsStyle
    let onInteraction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lyrics.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(style.plainFont)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, line.isBreak ? 8 : 0)
                }
                LyricsCredit(lyrics: lyrics)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 4)
            .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.vertical, 24, for: .scrollContent)
        .mask(LyricsFade())
        .modifier(HandScrollTracking(onScroll: onInteraction))
    }
}

// MARK: - Pieces

#if DEBUG
/// Where the lyrics on screen came from, how they're timed and whether
/// the cache answered — for checking the sources on a device.
private struct LyricsDebugBadge: View {
    private var service: LyricsService { .shared }

    private var text: String {
        let origin = service.origin?.rawValue ?? "…"
        switch service.state {
        case .loaded(let lyrics):
            let kind = lyrics.isInstrumental ? "instrumental" : lyrics.isWordTimed ? "word-timed" : lyrics.isSynced ? "timed" : "plain"
            let credit = lyrics.credit.map { " (\($0))" } ?? ""
            return "\(lyrics.source.rawValue)\(credit) · \(kind) · \(lyrics.lines.count) lines · \(origin)"
        case .none:
            return "none · \(service.isOnlineLookupEnabled ? "service + lrclib" : "service only") · \(origin)"
        case .loading:
            return "loading"
        case .failed:
            return "failed"
        case .unavailable:
            return "unavailable"
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
    }
}
#endif

/// Where the words came from, under the last line.
private struct LyricsCredit: View {
    let lyrics: Lyrics

    private var text: String {
        if let credit = lyrics.credit {
            return "Lyrics by \(credit)"
        }
        switch lyrics.source {
        case .plex: return "Lyrics from Plex"
        case .subsonic: return "Lyrics from your server"
        case .file: return "Lyrics from the file"
        case .lrclib: return "Lyrics from LRCLIB"
        }
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// Lines fade out at the top and bottom edges rather than being cut.
private struct LyricsFade: View {
    var body: some View {
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

// MARK: - Asking

extension Animation {
    /// Lyrics on and off, and the full-screen lyrics' controls away and
    /// back: quick and settled, with no overshoot.
    static let lyricsSwitch: Animation = .snappy(duration: 0.3)
}

extension AnyTransition {
    /// Text that swaps as lyrics go on or off — the title lines under the
    /// cover, the title beside the thumbnail. What leaves is gone in a
    /// tenth of a second; what comes waits until the cover has mostly
    /// moved, so the two never cross and the cover never passes over words.
    static let lyricsSwitch: AnyTransition = .asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.15)),
        removal: .opacity.animation(.easeIn(duration: 0.1))
    )

    /// The full-screen lyrics themselves: the same timing, rising a little
    /// into place as they come.
    static let lyricsBody: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .offset(y: 24)).animation(.easeOut(duration: 0.22).delay(0.15)),
        removal: .opacity.animation(.easeIn(duration: 0.1))
    )
}

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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the cover")

            Button(action: onToggleFullScreen) {
                Label(
                    isFullScreen ? "Show Controls" : "Full Screen",
                    systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                )
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

/// Keeps `LyricsService` asking for the song on screen while the player is
/// open, so the lyrics button knows whether there are any before it's
/// tapped. Asked again when the song's length arrives, which a speaker
/// sends a moment after the song changes.
struct LyricsRequestModifier: ViewModifier {
    @AppStorage(AppStorageKeys.lyricsShown) private var isShown: Bool = false

    private var route: PlaybackRoute { .shared }

    private struct Request: Equatable {
        let key: String?
        let hasDuration: Bool
    }

    func body(content: Content) -> some View {
        let controller = route.presented
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
                guard let next else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                LyricsService.shared.prefetch(next, duration: next.metadata?.duration.map(Self.seconds) ?? 0)
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

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }
}

/// The player's switch for lyrics in the artwork's place. Dimmed for a
/// song with none, and for a station — unless lyrics are on, so they can
/// still be turned off while the cover stands in.
struct LyricsButton: View {
    @AppStorage(AppStorageKeys.lyricsShown) private var isShown: Bool = false

    private var service: LyricsService { .shared }

    private var isAvailable: Bool {
        switch service.state {
        case .loaded, .loading, .failed: true
        case .none, .unavailable: false
        }
    }

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            withAnimation(.lyricsSwitch) {
                isShown.toggle()
            }
        } label: {
            Label("Lyrics", systemImage: isShown ? "quote.bubble.fill" : "quote.bubble")
                .labelStyle(.iconOnly)
#if targetEnvironment(macCatalyst)
                // An animated symbol swap costs the Mac ~90 MB of GPU memory.
                .contentTransition(.identity)
#else
                .contentTransition(.symbolEffect(.replace))
#endif
        }
        .disabled(!isAvailable && !isShown)
        .help("Lyrics")
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}
