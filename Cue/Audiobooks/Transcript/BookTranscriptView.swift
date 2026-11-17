import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
#if canImport(Translation) && !os(visionOS) && !targetEnvironment(macCatalyst)
import Translation
#endif

/// The typefaces a book's transcript can be read in.
enum BookTranscriptFont: String, CaseIterable, Identifiable {
    case system, rounded, serif, mono

    var id: Self { self }

    private var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    /// The face at `size`, made from a `UIFont` so it holds inside the
    /// player, whose `fontDesign(.rounded)` would otherwise win over a
    /// system font's design here.
    func font(size: CGFloat, weight: UIFont.Weight = .semibold) -> Font {
        Font(uiFont(size: size, weight: weight))
    }

    /// The face at `size`, for UIKit's text (Select Text's sheet).
    func uiFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "Mono"
        }
    }
}

/// A book's words as it plays (Cue Super), opened by the player's lyrics
/// button while a book plays: the same place and the same following as
/// timed lyrics (the line being read bright, the rest dim, kept near the
/// top, a finger scrolling stops the following and Back to Now starts it
/// again), read rather than sung. What it shows is `BookTranscriber`'s, which
/// runs only while this is on screen.
///
/// Unlike lyrics: the text can be set in another typeface, size and line
/// spacing (the Aa button); a tap on a word looks it up in the dictionary;
/// and a long press on a line opens its menu (`BookTranscriptLineMenu`):
/// Play from Here, Copy, Select Text, Share and Translate, since a tap is
/// the word's.
struct BookTranscriptView: View {
    var isFullScreen = false

    private var transcriber: BookTranscriber { .shared }

    var body: some View {
        ZStack {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Full screen, the button is in the header beside Full Screen
        // (`LyricsHeaderTitles`), not over the text.
        .overlay(alignment: .topTrailing) {
            if !isFullScreen, transcriber.state != .needsSuper, !transcriber.transcript.lines.isEmpty || transcriber.state != .unsupported {
                BookTranscriptSettingsButton()
            }
        }
        // Without Super: the preview's time left, and the way to Super.
        .overlay(alignment: .top) {
            if transcriber.isPreview, transcriber.state != .needsSuper, !transcriber.transcript.lines.isEmpty {
                BookTranscriptPreviewBadge(endsAt: transcriber.previewEndsAt)
                    .padding(.top, isFullScreen ? 4 : 8)
            }
        }
        .onAppear { transcriber.activate() }
        .onDisappear { transcriber.deactivate() }
    }

    @ViewBuilder
    private var content: some View {
        let transcript = transcriber.transcript
        switch transcriber.state {
        case .needsSuper where !transcript.lines.isEmpty:
            // The preview over: the text it reached, out of focus, behind
            // the way to Super.
            ZStack {
                BookTranscriptPreviewBackdrop(transcript: transcript)
                BookTranscriptUpsell(afterPreview: true, overText: true)
            }
        case .needsSuper:
            BookTranscriptUpsell(afterPreview: transcriber.isPreviewUsedUp)
        case .unsupported where transcript.lines.isEmpty:
            ContentUnavailableView(
                "Transcripts Aren't Available Here",
                systemImage: "captions.bubble",
                description: Text("Books are transcribed on the device, which needs iOS 26 or later on a recent iPhone, iPad or Mac.")
            )
        case .unavailable(let reason):
            ContentUnavailableView("No Transcript", systemImage: "captions.bubble", description: Text(reason))
        case .failed(let reason) where transcript.lines.isEmpty:
            ContentUnavailableView("Transcript Unavailable", systemImage: "exclamationmark.triangle", description: Text(reason))
        case .waitingForPlay where transcript.lines.isEmpty:
            ContentUnavailableView(
                "Play to Read Along",
                systemImage: "play.circle",
                description: Text("This book's words are heard as it plays. Download it to see them before they're read.")
            )
        case .downloadingModel(let fraction) where transcript.lines.isEmpty:
            VStack(spacing: 12) {
                ProgressView(value: fraction)
                    .frame(maxWidth: 220)
                Text("Getting the language ready on this device…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            if transcript.lines.isEmpty, transcriber.volatileText == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(transcriber.isLive ? "Listening…" : "Transcribing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                BookTranscriptFollower(isFullScreen: isFullScreen)
                    .id(transcriber.fileKey)
            }
        }
    }
}

// MARK: - Following

/// The lines, with the one being read and the word in it worked out ten
/// times a second from the player's own time (`exactPosition`), on the
/// file's time as the transcript is. The running clock that draws the
/// progress bar can be half a second out, a few words of a book. No lead is
/// added: the transcriber's word times are a fifth of a second or so ahead
/// of the voice already.
private struct BookTranscriptFollower: View {
    let isFullScreen: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let transcriber = BookTranscriber.shared
            let transcript = transcriber.transcript
            let position = PlaybackRoute.shared.presented.exactPosition(at: context.date)
            let current = transcript.lineIndex(at: position)
            BookTranscriptLines(
                transcript: transcript,
                revision: transcriber.revision,
                volatileText: transcriber.volatileText,
                current: current,
                spoken: current.map { index in
                    transcript.lines[index].words.lastIndex { ($0.start ?? .infinity) <= position }.map { $0 + 1 } ?? 0
                },
                isFullScreen: isFullScreen
            )
            .equatable()
        }
    }
}

/// The transcript's lines, drawn again only when what's in them or the line
/// being read changes. Lazy: a book's file can run to hours of lines.
private struct BookTranscriptLines: View, Equatable {
    let transcript: BookTranscript
    /// `BookTranscriber.revision`: compared in place of the transcript.
    let revision: Int
    let volatileText: String?
    let current: Int?
    /// How many of the current line's words have been said.
    let spoken: Int?
    let isFullScreen: Bool

    @AppStorage(AppStorageKeys.bookTranscriptFont) private var font: BookTranscriptFont = .serif
    @AppStorage(AppStorageKeys.bookTranscriptSize) private var size: Double = 24
    @AppStorage(AppStorageKeys.bookTranscriptSpacing) private var spacing: Double = 14
    @AppStorage(AppStorageKeys.bookTranscriptUnderline) private var underlines = true

    /// Following the line being read: off once a finger scrolls the lines,
    /// on again with Back to Now.
    @State private var isFollowing = true
    /// A word being looked up: marked in its line, which holds still at
    /// the top, with its definition in a card under it.
    @State private var lookup: LookupWord?
    /// When a word was last tapped, so a double tap isn't one word looked
    /// up and put away again.
    @State private var lookupAskedAt = Date.distantPast
    /// The definition is going: its card's page gives way to a picture first.
    @State private var isClosingLookup = false
    @State private var height: CGFloat = 0
    @State private var position = ScrollPosition(idType: BookTranscript.Line.ID.self)
    /// A finger, or the fling it left, is still moving the lines.
    @State private var isScrolling = false
    /// The lines at least half on screen.
    @State private var visibleLines: Set<BookTranscript.Line.ID> = []
    @State private var landingCheck: Task<Void, Never>?
    /// The line whose menu is open (a long press): bright over the rest,
    /// which dim, with its menu beside it. The lines hold still under it.
    @State private var menuLine: BookTranscript.Line.ID?
    /// The menu's size, measured, to place it beside the line.
    @State private var menuSize: CGSize = .zero
    /// A line asked to be translated, and the system's sheet for it: here
    /// rather than on the menu's button, which goes as the menu closes.
    @State private var translation = ""
    @State private var isTranslating = false
    /// The lines around one, opened to select from (Select Text).
    @State private var selecting: SelectableExcerpt?

    /// Where the line being read sits.
    private static let anchor = UnitPoint(x: 0.5, y: 0.2)
    /// Where a looked-up word's line sits, above its definition.
    private static let lookupAnchor = UnitPoint(x: 0.5, y: 0.04)
    /// How long a glide is given to land before it's checked.
    private static let landing: Duration = .milliseconds(650)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.volatileText == rhs.volatileText
            && lhs.current == rhs.current && lhs.spoken == rhs.spoken && lhs.isFullScreen == rhs.isFullScreen
    }

    /// Smaller in the cover's place than filling the phone.
    private var pointSize: CGFloat {
        isFullScreen ? size : size * 0.8
    }

    /// The line being read's id.
    private var currentID: BookTranscript.Line.ID? {
        current.flatMap { transcript.lines.indices.contains($0) ? transcript.lines[$0].id : nil }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(transcript.lines.enumerated()), id: \.element.id) { index, line in
                    BookTranscriptLineRow(
                        line: line,
                        emphasis: emphasis(of: index),
                        spoken: index == current ? spoken : nil,
                        underlines: underlines,
                        lookedUp: lookup?.line == line.id ? lookup?.index : nil,
                        font: font.font(size: pointSize)
                    )
                    .equatable()
                    .id(line.id)
#if targetEnvironment(macCatalyst)
                    .contextMenu { macLineMenu(line) }
#else
                    // Cue's own menu rather than the system's, whose lifted
                    // picture of the line flickered as the lines redrew
                    // under it. Alongside, so a scroll or a tap on a word
                    // still goes through.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in openMenu(on: line.id) }
                    )
                    .anchorPreference(key: MenuLineBounds.self, value: .bounds) { menuLine == line.id ? $0 : nil }
                    .accessibilityAction(named: "Line Actions") { openMenu(on: line.id) }
#endif
                }
                if let volatileText {
                    Text(volatileText)
                        .font(font.font(size: pointSize))
                        .foregroundStyle(.primary.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 4)
            .padding(.top, isFullScreen ? 8 : 36)
            // Room for the last lines to scroll up above a definition.
            .padding(.bottom, lookup == nil ? 240 : max(240, height))
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .fadingScrollEdges()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onScrollTargetVisibilityChange(idType: BookTranscript.Line.ID.self, threshold: 0.5) { visibleLines = Set($0) }
        .onScrollPhaseChange { _, phase in
            // Not `.tracking`: that's any touch, a tap on a word too.
            if phase == .interacting {
                isFollowing = false
                landingCheck?.cancel()
                closeMenu()
            }
            isScrolling = phase == .interacting || phase == .decelerating
        }
        // Opens on the line being read, then glides to each one after.
        .onChange(of: current, initial: true) { old, _ in
            guard isFollowing, lookup == nil, menuLine == nil, let currentID else { return }
            scroll(to: currentID, glides: old != nil)
        }
        // Back to the line being read once a menu closes.
        .onChange(of: menuLine) {
            guard menuLine == nil, isFollowing, lookup == nil, let currentID else { return }
            scroll(to: currentID)
        }
        // A line heard again replaces the one before: a menu open on it goes.
        .onChange(of: revision) {
            if let menuLine, line(withID: menuLine) == nil { closeMenu() }
        }
        .overlay(alignment: .bottom) {
            if !isFollowing, lookup == nil {
                Button("Back to Now", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    HapticManager.shared.fireHaptic(.selection)
                    isFollowing = true
                    if let currentID { scroll(to: currentID) }
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
        .animation(.smooth(duration: 0.25), value: isFollowing)
        // The word's definition in place of the lower part of the text.
        .overlay(alignment: .bottom) {
            if let lookup {
                // Only while it's still this word's: opening another
                // word's card takes the last one's page away too.
                BookTranscriptDefinitionCard(word: lookup, isClosing: isClosingLookup) { [id = lookup.id] in
                    guard self.lookup?.id == id else { return }
                    closeLookup()
                }
                .frame(height: max(240, height * 0.6))
                // Quick: a definition is wanted now.
                .transition(.opacity)
            }
        }
        // The word's line to the top, above the card; back to the line
        // being read once it closes.
        .onChange(of: lookup?.id) {
            if let lookup {
                scroll(to: lookup.line, anchor: Self.lookupAnchor)
            } else if isFollowing, menuLine == nil, let currentID {
                scroll(to: currentID)
            }
        }
#if !targetEnvironment(macCatalyst)
        // A line's menu beside the line, over the rest dimmed; a tap or a
        // drag anywhere else puts it away.
        .overlayPreferenceValue(MenuLineBounds.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let menuLine, let target = self.line(withID: menuLine) {
                    let rect = proxy[anchor]
                    let origin = proxy.frame(in: .global).origin
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(.rect)
                            .gesture(DragGesture(minimumDistance: 0).onEnded { _ in closeMenu() })
                        BookTranscriptLineMenu { action in
                            perform(action, on: target, from: rect.offsetBy(dx: origin.x, dy: origin.y))
                        }
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { menuSize = $0 }
                        .offset(menuOffset(beside: rect, in: proxy.size))
                        // Placed once it's measured.
                        .opacity(menuSize == .zero ? 0 : 1)
                    }
                    .transition(.opacity)
                }
            }
        }
#endif
#if canImport(Translation) && !os(visionOS) && !targetEnvironment(macCatalyst)
        .translationPresentation(isPresented: $isTranslating, text: translation)
#endif
        .sheet(item: $selecting) { excerpt in
            BookTranscriptSelectSheet(excerpt: excerpt, font: font.uiFont(size: CGFloat(min(size, 26)), weight: .regular))
        }
        .onDisappear { landingCheck?.cancel() }
        // A tap on a word: its link, opened here as a lookup. Another word
        // shows its definition instead; the same word again puts it away.
        // Not while a line's menu is open: the long press that opened it
        // can end as a tap on the word under the finger.
        .environment(\.openURL, OpenURLAction { url in
            guard let word = BookTranscriptLineRow.lookup(in: url) else { return .systemAction }
            guard menuLine == nil else { return .handled }
            guard Date.now.timeIntervalSince(lookupAskedAt) > 0.4 else { return .handled }
            lookupAskedAt = .now
            HapticManager.shared.fireHaptic(.selection)
            if lookup?.line == word.line && lookup?.index == word.index {
                closeLookup()
            } else {
                withAnimation(.easeOut(duration: 0.15)) { lookup = word }
                remember(word)
            }
            return .handled
        })
    }

    /// Keeps a word looked up with the words around it and its line's
    /// place in the book (`BookWordLookups`), for the book's history to
    /// show again.
    private func remember(_ word: LookupWord) {
        guard let index = transcript.lineIndex(at: word.line), transcript.lines[index].id == word.line else { return }
        let line = transcript.lines[index]
        guard line.words.indices.contains(word.index), let place = BookTranscriptLineRow.bookTime(of: line.start) else { return }
        let context = BookTranscriptLineRow.context(of: line, at: word.index)
        BookWordLookups.shared.record(word.term, before: context.before, after: context.after, at: place.time, in: place.book)
    }

    /// Puts the definition away: its page gives way to a still picture in
    /// the card first, a frame before the card goes, so the two leave as one.
    private func closeLookup() {
        guard lookup != nil, !isClosingLookup else { return }
        isClosingLookup = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeOut(duration: 0.15)) { lookup = nil }
            isClosingLookup = false
        }
    }

    /// Puts line `id` at `anchor`, gliding unless told not to, as the
    /// lyrics do: a fling still running would carry on over a glide, so
    /// it's stopped where it is first; and a glide is aimed by estimated
    /// heights across lines not built yet, so it's checked once it should
    /// have landed, and the line jumped to if it isn't on screen.
    private func scroll(to id: BookTranscript.Line.ID, anchor: UnitPoint = Self.anchor, glides: Bool = true) {
        defer { checkLanding(on: id, anchor: anchor) }
        guard glides else { return jump(to: id, anchor: anchor) }
        guard isScrolling, let top = visibleLines.min() else { return glide(to: id, anchor: anchor) }
        jump(to: top, anchor: .top)
        Task { glide(to: id, anchor: anchor) }
    }

    private func glide(to id: BookTranscript.Line.ID, anchor: UnitPoint) {
        withAnimation(.smooth(duration: 0.45)) {
            position.scrollTo(id: id, anchor: anchor)
        }
    }

    private func jump(to id: BookTranscript.Line.ID, anchor: UnitPoint) {
        withTransaction(\.disablesAnimations, true) {
            position.scrollTo(id: id, anchor: anchor)
        }
    }

    /// Once the scroll should have landed, the line is on screen, or it's
    /// jumped to, unless a finger has taken over since.
    private func checkLanding(on id: BookTranscript.Line.ID, anchor: UnitPoint) {
        landingCheck?.cancel()
        landingCheck = Task {
            try? await Task.sleep(for: Self.landing)
            guard !Task.isCancelled, !isScrolling, !visibleLines.contains(id) else { return }
            jump(to: id, anchor: anchor)
        }
    }

    /// How bright a line is: the one being read full, the rest dim; the
    /// one with a word looked up full too. With a line's menu open, that
    /// line alone, the rest dimmer still.
    private func emphasis(of index: Int) -> Double {
        if let menuLine { return transcript.lines[index].id == menuLine ? 1 : 0.25 }
        if lookup?.line == transcript.lines[index].id { return 1 }
        guard let current else { return 0.85 }
        return index == current ? 1 : 0.4
    }

    /// The line with id `id`, while the transcript still has it.
    private func line(withID id: BookTranscript.Line.ID) -> BookTranscript.Line? {
        guard let index = transcript.lineIndex(at: id), transcript.lines[index].id == id else { return nil }
        return transcript.lines[index]
    }

    private func openMenu(on id: BookTranscript.Line.ID) {
        guard menuLine != id else { return }
        HapticManager.shared.fireHaptic(.buttonPress)
        if lookup != nil { closeLookup() }
        withAnimation(.smooth(duration: 0.2)) { menuLine = id }
    }

    private func closeMenu() {
        guard menuLine != nil else { return }
        withAnimation(.smooth(duration: 0.2)) { menuLine = nil }
    }

    /// Where the menu goes: under the line where it fits, else over it,
    /// else as low as it fits; from the line's leading edge, kept on screen.
    private func menuOffset(beside line: CGRect, in size: CGSize) -> CGSize {
        let margin: CGFloat = 8
        let below = line.maxY + margin
        let above = line.minY - margin - menuSize.height
        let y = if below + menuSize.height <= size.height - margin {
            below
        } else if above >= margin {
            above
        } else {
            max(margin, size.height - menuSize.height - margin)
        }
        let x = min(max(margin, line.minX), max(margin, size.width - menuSize.width - margin))
        return CGSize(width: x, height: y)
    }

    /// A menu's choice for `line`; `frame` is the line's, in the window,
    /// for the share sheet to point at on iPad.
    private func perform(_ action: BookTranscriptLineMenu.Action, on line: BookTranscript.Line, from frame: CGRect) {
        closeMenu()
        switch action {
        case .play:
            isFollowing = true
            Task { await BookTranscriptLineRow.play(from: line.start) }
        case .copy:
            UIPasteboard.general.string = line.text
        case .select:
            selecting = SelectableExcerpt(around: line.id, in: transcript)
        case .share:
            TranscriptShareSheet.present(line.text, from: frame)
        case .translate:
            translation = line.text
            isTranslating = true
        }
    }

#if targetEnvironment(macCatalyst)
    /// The Mac's menu for a line, a right-click's: the system's, as on any
    /// Mac. No Translate: Catalyst hasn't the system's translation sheet.
    @ViewBuilder
    private func macLineMenu(_ line: BookTranscript.Line) -> some View {
        Button("Play from Here", systemImage: "play") {
            isFollowing = true
            Task { await BookTranscriptLineRow.play(from: line.start) }
        }
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = line.text
        }
        Button("Select Text", systemImage: "selection.pin.in.out") {
            selecting = SelectableExcerpt(around: line.id, in: transcript)
        }
        ShareLink(item: line.text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
#endif
}

// MARK: - A Line's Menu

/// The bounds of the line whose menu is open, for the menu to sit beside.
private struct MenuLineBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A line's actions, beside it, after a long press. Cue's own rather than
/// the system's context menu: that one lifted a picture of the line that
/// flickered as the transcript redrew under it, and never said it had
/// closed, so the lines couldn't be held still for it.
private struct BookTranscriptLineMenu: View {
    enum Action {
        case play, copy, select, share, translate
    }

    let onAction: (Action) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row("Play from Here", systemImage: "play", .play)
            Divider()
            row("Copy", systemImage: "doc.on.doc", .copy)
            Divider()
            row("Select Text", systemImage: "selection.pin.in.out", .select)
            Divider()
            row("Share", systemImage: "square.and.arrow.up", .share)
#if canImport(Translation) && !os(visionOS) && !targetEnvironment(macCatalyst)
            Divider()
            row("Translate", systemImage: "translate", .translate)
#endif
        }
        .frame(width: 250)
        // The player's rounded design is for its own titles; a menu reads
        // as the system's do.
        .fontDesign(.default)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
#if os(visionOS)
        .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
#else
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
#endif
        .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, _ action: Action) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Image(systemName: systemImage)
                    .frame(width: 24)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(LineMenuRowStyle())
    }
}

/// A menu row, lit while pressed, as the system's are.
private struct LineMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : .clear)
    }
}

/// The system's share sheet, presented over whatever is on top: from the
/// menu, which goes as it's chosen, a `ShareLink` would have gone with it.
/// On iPad it points at the line.
@MainActor
private enum TranscriptShareSheet {
    static func present(_ text: String, from frame: CGRect) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.keyWindow ?? scene?.windows.first, var top = window.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = frame
        }
        top.present(sheet, animated: true)
    }
}

// MARK: - Select Text

/// The lines around one, as one passage to select from, the line itself
/// selected to begin with.
private struct SelectableExcerpt: Identifiable {
    let id = UUID()
    let text: String
    /// The line's place in `text`, in UTF-16, as UIKit counts.
    let selection: NSRange

    /// How many lines either side of the line come with it.
    private static let reach = 8

    init?(around id: BookTranscript.Line.ID, in transcript: BookTranscript) {
        guard let index = transcript.lineIndex(at: id), transcript.lines[index].id == id else { return nil }
        let lines = transcript.lines
        var text = ""
        var selection = NSRange(location: 0, length: 0)
        for place in max(0, index - Self.reach) ... min(lines.count - 1, index + Self.reach) {
            let line = lines[place].text
            guard !line.isEmpty else { continue }
            if !text.isEmpty { text += " " }
            if place == index {
                selection = NSRange(location: text.utf16.count, length: line.utf16.count)
            }
            text += line
        }
        self.text = text
        self.selection = selection
    }
}

/// Select Text: the passage around a line, still and selectable a word at
/// a time, which the live transcript can't be (SwiftUI's text on iPhone
/// copies a line whole, and a line redrawn as it's read would drop the
/// selection). What's selected gets the system's own menu: Copy, Look Up,
/// Translate, Share.
private struct BookTranscriptSelectSheet: View {
    let excerpt: SelectableExcerpt
    let font: UIFont
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: excerpt.text, selection: excerpt.selection, font: font)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A passage in a read-only text view, selectable.
private struct SelectableTextView: UIViewRepresentable {
    let text: String
    let selection: NSRange
    let font: UIFont

    func makeUIView(context: Context) -> ExcerptTextView {
        let view = ExcerptTextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 40, right: 16)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        view.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ])
        view.initialSelection = selection
        return view
    }

    func updateUIView(_ view: ExcerptTextView, context: Context) {}
}

/// Selects its first selection once it's on screen: a selection made
/// before shows no handles.
private final class ExcerptTextView: UITextView {
    var initialSelection: NSRange?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, let range = initialSelection else { return }
        initialSelection = nil
        // After the sheet's first layout, so the range scrolls into view.
        Task { @MainActor [weak self] in
            guard let self else { return }
            becomeFirstResponder()
            selectedRange = range
            scrollRangeToVisible(range)
        }
    }
}

/// One line, its words links for a tap to look up. `emphasis` is how bright
/// it's drawn; `spoken`, on the line being read, how many of its words have
/// been said, those drawn bright and the rest dimmer, the one being said
/// underlined too with `underlines` (not on the Mac, where text redrawn as
/// it's read costs a burst of GPU memory). It's drawn again only when one of
/// those or the line changes.
private struct BookTranscriptLineRow: View, Equatable {
    let line: BookTranscript.Line
    let emphasis: Double
    let spoken: Int?
    let underlines: Bool
    /// The word being looked up, marked as with a highlighter.
    let lookedUp: Int?
    let font: Font

    private static let scheme = "cue-lookup"

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line && lhs.emphasis == rhs.emphasis && lhs.spoken == rhs.spoken
            && lhs.underlines == rhs.underlines && lhs.lookedUp == rhs.lookedUp && lhs.font == rhs.font
    }

    var body: some View {
        text
            .font(font)
            .tint(.primary)
            .foregroundStyle(.primary)
            .opacity(emphasis)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeOut(duration: 0.25), value: emphasis)
            .accessibilityAction(named: "Play from Here") {
                Task { await Self.play(from: line.start) }
            }
    }

    @ViewBuilder
    private var text: some View {
#if targetEnvironment(macCatalyst)
        Text(Self.linked(line, marking: lookedUp))
#else
        if let spoken {
            Self.words(line, marking: lookedUp).textRenderer(SpokenWords(spoken: spoken, underlines: underlines))
        } else {
            Text(Self.linked(line, marking: lookedUp))
        }
#endif
    }

    /// The line a word at a time, each part tagged with its word's place
    /// and whether it's the word itself, for `SpokenWords` to tell the said
    /// from the unsaid and to underline the word, not its spacing.
    private static func words(_ line: BookTranscript.Line, marking marked: Int?) -> Text {
        var text = Text(verbatim: "")
        for index in line.words.indices {
            let parts = parts(of: line, at: index, marked: index == marked)
            let leading = Text(verbatim: parts.leading).customAttribute(WordPlace(index: index, isWord: false))
            let word = Text(parts.word).customAttribute(WordPlace(index: index, isWord: true))
            let trailing = Text(verbatim: parts.trailing).customAttribute(WordPlace(index: index, isWord: false))
            text = Text("\(text)\(leading)\(word)\(trailing)")
        }
        return text
    }

    /// The line with each word a link to itself, its spacing and
    /// punctuation left out of the link.
    private static func linked(_ line: BookTranscript.Line, marking marked: Int?) -> AttributedString {
        var text = AttributedString()
        for index in line.words.indices {
            let parts = parts(of: line, at: index, marked: index == marked)
            text.append(AttributedString(parts.leading))
            text.append(parts.word)
            text.append(AttributedString(parts.trailing))
        }
        return text
    }

    /// Word `index` of the line in three: what comes before it (its space,
    /// an opening quote), the word itself as a link to look it up from this
    /// line, highlighted when `marked`, and what follows (its punctuation).
    private static func parts(of line: BookTranscript.Line, at index: Int, marked: Bool) -> (leading: String, word: AttributedString, trailing: String) {
        let pieces = Self.split(line, at: index)
        var word = AttributedString(pieces.core)
        if !pieces.core.isEmpty {
            var components = URLComponents()
            components.scheme = scheme
            components.host = "word"
            components.queryItems = [URLQueryItem(name: "term", value: pieces.core), URLQueryItem(name: "line", value: String(line.id)), URLQueryItem(name: "word", value: String(index))]
            word.link = components.url
            if marked {
                word.backgroundColor = Color.yellow.opacity(0.4)
            }
        }
        return (pieces.leading, word, pieces.trailing)
    }

    /// Word `index` of the line as text in three: what comes before it, the
    /// word, and what follows.
    private static func split(_ line: BookTranscript.Line, at index: Int) -> (leading: String, core: String, trailing: String) {
        var raw = line.words[index].text
        if index == 0 {
            raw = String(raw.drop { $0.isWhitespace })
        }
        let leading = raw.prefix { !$0.isLetter && !$0.isNumber }
        let rest = raw.dropFirst(leading.count)
        let core = rest.prefix { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-" }
        let trailing = rest.dropFirst(core.count)
        return (String(leading), String(core), String(trailing))
    }

    /// The words either side of word `index` in its line, as a lookup keeps
    /// them: `reach` each way, with "…" where the line goes on.
    static func context(of line: BookTranscript.Line, at index: Int, reach: Int = 6) -> (before: String, after: String) {
        let pieces = Self.split(line, at: index)
        let first = max(0, index - reach)
        let last = min(line.words.count, index + 1 + reach)
        var before = String((line.words[first ..< index].map(\.text).joined() + pieces.leading).drop { $0.isWhitespace })
        if first > 0 { before = "…" + before }
        var after = pieces.trailing + line.words[(index + 1) ..< last].map(\.text).joined()
        while after.last?.isWhitespace == true { after.removeLast() }
        if last < line.words.count { after += "…" }
        return (before, after)
    }

    /// The word a tapped link stands for, and its line.
    static func lookup(in url: URL) -> LookupWord? {
        guard url.scheme == scheme, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let term = items.first(where: { $0.name == "term" })?.value,
              let line = items.first(where: { $0.name == "line" })?.value.flatMap(TimeInterval.init),
              let index = items.first(where: { $0.name == "word" })?.value.flatMap(Int.init) else { return nil }
        return LookupWord(term: term, line: line, index: index)
    }

    /// Plays from `fileTime` in the file playing: through the book player,
    /// so the place left joins the book's history.
    @MainActor
    static func play(from fileTime: TimeInterval) async {
        guard let place = bookTime(of: max(fileTime - 0.3, 0)) else { return }
        await AudiobookPlayer.shared.jump(to: place.time)
    }

    /// The loaded book, and where `fileTime` in the file playing is in it.
    @MainActor
    static func bookTime(of fileTime: TimeInterval) -> (book: PlayableContent, time: TimeInterval)? {
        let controller = PlaybackRoute.shared.presented
        guard let book = AudiobookPlayer.shared.current, let part = book.partIndex(of: controller.nowPlayingDisplay) else { return nil }
        return (book.book, book.time(part: part, offset: fileTime))
    }
}

/// A word's place in its line, on its run of text, and whether the run is
/// the word itself rather than its spacing or punctuation.
private struct WordPlace: TextAttribute {
    let index: Int
    let isWord: Bool
}

/// Draws the line being read with the word being said brightest, the words
/// said before it a little dimmer and the rest dimmer still, and with
/// `underlines` a line under the word being said. Changes only as a word
/// starts, not every frame.
private struct SpokenWords: TextRenderer {
    let spoken: Int
    let underlines: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                var copy = context
                let place = run[WordPlace.self]
                let index = place?.index ?? 0
                let isCurrent = index == spoken - 1
                copy.opacity = isCurrent ? 1 : index < spoken ? 0.8 : 0.5
                copy.draw(run)
                if underlines, isCurrent, place?.isWord == true {
                    let bounds = run.typographicBounds
                    let thickness = max(1.5, (bounds.ascent + bounds.descent) * 0.06)
                    let underline = CGRect(x: bounds.rect.minX, y: bounds.origin.y + bounds.descent * 0.4, width: bounds.width, height: thickness)
                    copy.fill(Path(roundedRect: underline, cornerRadius: thickness / 2), with: .foreground)
                }
            }
        }
    }
}

// MARK: - Look Up and Translate

/// A word tapped to look up, and the line it's in, which its definition
/// points at.
private struct LookupWord: Identifiable {
    let id = UUID()
    let term: String
    let line: BookTranscript.Line.ID
    /// The word's place in its line, to mark it there.
    let index: Int
}

/// A word's definition in place of the lower part of the transcript, the
/// word marked in its line above it. A card of Cue's own rather than a
/// popover: iOS squeezed a popover near the screen's edges until the
/// dictionary's page was cut off. The page itself is presented only within
/// the card (`DictionaryCardController`). Its grabber, the page's Done, or
/// the same word tapped again puts it away.
private struct BookTranscriptDefinitionCard: View {
    let word: LookupWord
    /// About to go: its page gives way to a picture the card carries off.
    var isClosing = false
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // A strip of its own over the page, to swipe the card down: the
            // page, presented, sits above anything drawn on it and takes
            // its touches. The card goes with the swipe rather than
            // following the finger, which the page wouldn't.
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 8).onEnded { value in
                        if value.translation.height > 30 || value.predictedEndTranslation.height > 120 {
                            onClose()
                        }
                    }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close Definition")
                .accessibilityAction { onClose() }
#if targetEnvironment(macCatalyst)
            // The page only opens Dictionary on the Mac: the entry, set by Cue.
            DictionaryDefinitionView(term: word.term, onClose: onClose)
#else
            DictionaryLookup(term: word.term, isClosing: isClosing, onClose: onClose)
#endif
        }
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
    }
}

/// The system dictionary's page for a word: the only way to a definition
/// iOS offers (it gives no definition text to lay out), shown in Cue's own
/// card (`DictionaryCardController`).
private struct DictionaryLookup: UIViewControllerRepresentable {
    let term: String
    /// The card is about to go: the page gives way to its picture.
    let isClosing: Bool
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> DictionaryCardController {
        DictionaryCardController(term: term, onClose: onClose)
    }

    func updateUIViewController(_ controller: DictionaryCardController, context: Context) {
        controller.onClose = onClose
        if isClosing {
            controller.takePageDown(leavingPicture: true)
        } else {
            controller.show(term)
        }
    }

    static func dismantleUIViewController(_ controller: DictionaryCardController, coordinator: ()) {
        controller.close()
    }
}

/// Holds the dictionary's page in the card. The page is presented, as its
/// Done expects, but over this controller's bounds alone (`.overCurrentContext`
/// in the context it defines), so Done dismisses only the page, and the
/// card closes with it. Merely added to a view, the page's Done dismissed
/// the nearest presentation around it: the whole player.
///
/// One card for a lookup, another word's page taking the last one's place
/// once it's gone (`show(_:)`): a second page opened while the first was
/// still up never loaded.
///
/// The page doesn't move with the card, so before the card goes the page
/// gives way to a still picture of it in the card's own view, which does:
/// otherwise the page went first and the empty card after.
private final class DictionaryCardController: UIViewController {
    private var term: String
    var onClose: (() -> Void)?
    private var page: DictionaryPage?

    init(term: String, onClose: @escaping () -> Void) {
        self.term = term
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        definesPresentationContext = true
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if page == nil { presentPage() }
    }

    /// Shows `term`'s page in place of the one up.
    func show(_ term: String) {
        guard term != self.term else { return }
        self.term = term
        // Not up yet: it comes up with this term.
        guard page != nil else { return }
        takePageDown(leavingPicture: false) { [weak self] in
            guard let self, self.view.window != nil else { return }
            self.presentPage()
        }
    }

    /// Takes the page down at once, without closing the card; with
    /// `leavingPicture`, a still of it stays in its place for the card to
    /// carry off.
    func takePageDown(leavingPicture: Bool, then: (() -> Void)? = nil) {
        guard let page, presentedViewController === page else { return }
        if leavingPicture { leavePicture(of: page) }
        page.onLeaving = nil
        dismiss(animated: false) { then?() }
        self.page = nil
    }

    private func leavePicture(of page: UIViewController) {
        guard let picture = page.view.snapshotView(afterScreenUpdates: false) else { return }
        picture.frame = view.bounds
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(picture)
    }

    private func presentPage() {
        let page = DictionaryPage(term: term)
        page.modalPresentationStyle = .overCurrentContext
        // Its Done: as the page starts to go, its picture takes its place
        // and the card closes; the page itself goes at once
        // (`InstantDismissal`), and the card fades out with the still. Only
        // Done, with the card up: this controller taking the page down
        // clears it first.
        page.transitioningDelegate = InstantDismissal.shared
        page.onLeaving = { [weak self, weak page] in
            guard let self, let page, self.parent != nil, self.view.window != nil else { return }
            self.leavePicture(of: page)
            self.page = nil
            self.onClose?()
        }
        self.page = page
        present(page, animated: false)
    }

    /// Takes the page down without closing the card again: the card is
    /// already gone.
    func close() {
        onClose = nil
        takePageDown(leavingPicture: false)
    }
}

/// Takes the dictionary's page away at once when its Done dismisses it:
/// the card, holding a still of the page, does the fading, so the two can't
/// fall out of step.
private final class InstantDismissal: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
    static let shared = InstantDismissal()

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        self
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        0
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        context.view(forKey: .from)?.removeFromSuperview()
        context.completeTransition(!context.transitionWasCancelled)
    }
}

/// The dictionary's page, saying when it starts to go.
private final class DictionaryPage: UIReferenceLibraryViewController {
    var onLeaving: (() -> Void)?

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            onLeaving?()
        }
    }
}

// MARK: - Settings

/// The Aa button: the typeface, size and line spacing, and the book's
/// language. `inHeader`, it's drawn as the full-screen header's buttons are.
struct BookTranscriptSettingsButton: View {
    var inHeader = false
    @State private var isPresented = false

    var body: some View {
        if inHeader {
            button
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        } else {
            button
                .font(.body.weight(.semibold))
                .padding(8)
#if os(visionOS)
                .buttonStyle(.bordered)
#else
                .buttonStyle(.glass)
#endif
                .buttonBorderShape(.circle)
        }
    }

    private var button: some View {
        Button("Text Settings", systemImage: "textformat.size") {
            isPresented = true
        }
        .labelStyle(.iconOnly)
        .popover(isPresented: $isPresented) {
            BookTranscriptSettings()
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct BookTranscriptSettings: View {
    @AppStorage(AppStorageKeys.bookTranscriptFont) private var font: BookTranscriptFont = .serif
    @AppStorage(AppStorageKeys.bookTranscriptSize) private var size: Double = 24
    @AppStorage(AppStorageKeys.bookTranscriptSpacing) private var spacing: Double = 14
    @AppStorage(AppStorageKeys.bookTranscriptUnderline) private var underlines = true

    private var transcriber: BookTranscriber { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ForEach(BookTranscriptFont.allCases) { option in
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        font = option
                    } label: {
                        VStack(spacing: 4) {
                            Text("Aa")
                                .font(option.font(size: 22))
                            Text(option.title)
                                .font(.caption2)
                        }
                        .frame(width: 58, height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(option == font ? Color.accent.opacity(0.2) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(option == font ? Color.accent : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == font ? .isSelected : [])
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $size, in: 16...40, step: 1)
                Image(systemName: "textformat.size.larger")
            }
            .accessibilityElement(children: .contain)

            HStack(spacing: 10) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .imageScale(.small)
                Slider(value: $spacing, in: 4...32, step: 2)
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .imageScale(.large)
            }
            .accessibilityLabel("Line Spacing")

#if !targetEnvironment(macCatalyst)
            // The Mac doesn't light the word being said (see
            // `BookTranscriptLineRow`), so it has nothing to underline.
            Toggle("Underline Word", systemImage: "underline", isOn: $underlines)
#endif

            if !transcriber.supportedLocales.isEmpty {
                Menu {
                    ForEach(transcriber.supportedLocales, id: \.identifier) { locale in
                        Button(LiveTranscriptionService.displayName(for: locale)) {
                            transcriber.setLocale(locale)
                        }
                    }
                } label: {
                    HStack {
                        Label("Language", systemImage: "globe")
                        Spacer()
                        Text(transcriber.locale.map(LiveTranscriptionService.displayName(for:)) ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}

// MARK: - Super

/// Without Super, while the preview runs: how long it has left, and a tap
/// to Super.
private struct BookTranscriptPreviewBadge: View {
    let endsAt: Date?

    var body: some View {
        Button {
            FeatureGate.shared.presentPaywall(PaywallReason(feature: .bookTranscript))
        } label: {
            // Once a second, and only the badge.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let endsAt {
                    let left = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
                    Label("Preview \(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))", systemImage: "sparkles")
                } else {
                    Label("Preview", systemImage: "sparkles")
                }
            }
            .font(.caption.bold())
            .monospacedDigit()
        }
#if os(visionOS)
        .buttonStyle(.bordered)
#else
        .buttonStyle(.glass)
#endif
        .buttonBorderShape(.capsule)
        .accessibilityHint("Opens Cue Super")
    }
}

/// The text the preview reached, still and out of focus behind the way to
/// Super: the lines about where the book is, drawn once, with nothing
/// following the player under the blur.
private struct BookTranscriptPreviewBackdrop: View {
    let transcript: BookTranscript

    @AppStorage(AppStorageKeys.bookTranscriptFont) private var font: BookTranscriptFont = .serif
    @AppStorage(AppStorageKeys.bookTranscriptSize) private var size: Double = 24
    @AppStorage(AppStorageKeys.bookTranscriptSpacing) private var spacing: Double = 14

    var body: some View {
        let position = PlaybackRoute.shared.presented.exactPosition(at: .now)
        let current = transcript.lineIndex(at: position) ?? 0
        let shown = transcript.lines[max(0, current - 1) ..< min(transcript.lines.count, current + 8)]
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(shown) { line in
                Text(line.text)
            }
        }
        .font(font.font(size: size * 0.8))
        .foregroundStyle(.primary.opacity(0.35))
        // Room for the blur to fade out inside the frame, which the edge
        // mask otherwise cuts straight.
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .blur(radius: 10)
        .fadingScrollEdges()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the transcript is, for someone without Cue Super, and the way to it;
/// `afterPreview`, once the day's preview has run; `overText`, on a card of
/// its own over the text the preview reached, which made it hard to read.
/// Opacities of primary rather than `.secondary`, whose vibrancy takes on
/// what's under it.
private struct BookTranscriptUpsell: View {
    var afterPreview = false
    var overText = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text(afterPreview ? "Keep Reading Along" : "Read Along")
                .font(.title2.bold())
            Text("Every word of the book as it's read, transcribed privately on this device. Tap a word to look it up.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Get Cue Super") {
                FeatureGate.shared.presentPaywall(PaywallReason(feature: .bookTranscript))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            if afterPreview {
                Text("Your free preview is back tomorrow.")
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .padding(24)
        .background {
            if overText {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 6)
            }
        }
        .padding(.horizontal, overText ? 16 : 0)
        .frame(maxWidth: 380)
    }
}
