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
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return Font(UIFont(descriptor: descriptor, size: size))
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
/// and a long press on a line offers Play from Here, Copy, Translate and
/// Share, since a tap is the word's.
struct BookTranscriptView: View {
    var isFullScreen = false
    /// A finger on the transcript, for the full-screen player to bring its
    /// controls back.
    var onInteraction: () -> Void = {}

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
        .onAppear { transcriber.activate() }
        .onDisappear { transcriber.deactivate() }
    }

    @ViewBuilder
    private var content: some View {
        let transcript = transcriber.transcript
        switch transcriber.state {
        case .needsSuper:
            BookTranscriptUpsell()
        case .unsupported where transcript.lines.isEmpty:
            ContentUnavailableView(
                "Transcripts Aren't Available Here",
                systemImage: "text.quote",
                description: Text("Books are transcribed on the device, which needs iOS 26 or later on a recent iPhone, iPad or Mac.")
            )
        case .unavailable(let reason):
            ContentUnavailableView("No Transcript", systemImage: "text.quote", description: Text(reason))
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
                BookTranscriptFollower(isFullScreen: isFullScreen, onInteraction: onInteraction)
                    .id(transcriber.fileKey)
            }
        }
    }
}

// MARK: - Following

/// The lines, with the one being read and the word in it worked out ten
/// times a second from the player's clock, on the file's time as the
/// transcript is.
private struct BookTranscriptFollower: View {
    let isFullScreen: Bool
    let onInteraction: () -> Void

    /// A moment ahead, so the eye is on a word as it's said.
    private static let lead: TimeInterval = 0.15

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let transcriber = BookTranscriber.shared
            let transcript = transcriber.transcript
            let position = PlaybackRoute.shared.presented.position(at: context.date) + Self.lead
            let current = transcript.lineIndex(at: position)
            BookTranscriptLines(
                transcript: transcript,
                revision: transcriber.revision,
                volatileText: transcriber.volatileText,
                current: current,
                spoken: current.map { index in
                    transcript.lines[index].words.lastIndex { ($0.start ?? .infinity) <= position }.map { $0 + 1 } ?? 0
                },
                isFullScreen: isFullScreen,
                onInteraction: onInteraction
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
    let onInteraction: () -> Void

    @AppStorage(AppStorageKeys.bookTranscriptFont) private var font: BookTranscriptFont = .serif
    @AppStorage(AppStorageKeys.bookTranscriptSize) private var size: Double = 24
    @AppStorage(AppStorageKeys.bookTranscriptSpacing) private var spacing: Double = 14

    @State private var isFollowing = true
    @State private var lookup: LookupWord?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.volatileText == rhs.volatileText
            && lhs.current == rhs.current && lhs.spoken == rhs.spoken && lhs.isFullScreen == rhs.isFullScreen
    }

    /// Smaller in the cover's place than filling the phone.
    private var pointSize: CGFloat {
        isFullScreen ? size : size * 0.8
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(transcript.lines.enumerated()), id: \.element.id) { index, line in
                        BookTranscriptLineRow(
                            line: line,
                            emphasis: emphasis(of: index),
                            spoken: index == current ? spoken : nil,
                            font: font.font(size: pointSize)
                        )
                        .equatable()
                        .id(line.id)
                        .contextMenu { lineMenu(line) }
                    }
                    if let volatileText {
                        Text(volatileText)
                            .font(font.font(size: pointSize))
                            .foregroundStyle(.primary.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, isFullScreen ? 8 : 36)
                .padding(.bottom, 240)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    isFollowing = false
                    onInteraction()
                }
            }
            .onChange(of: current, initial: true) { old, current in
                guard isFollowing, let current, transcript.lines.indices.contains(current) else { return }
                let id = transcript.lines[current].id
                if old == nil {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.2))
                } else {
                    withAnimation(.smooth(duration: 0.5)) {
                        proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.2))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !isFollowing {
                    Button("Back to Now", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        isFollowing = true
                        if let current, transcript.lines.indices.contains(current) {
                            withAnimation(.smooth(duration: 0.5)) {
                                proxy.scrollTo(transcript.lines[current].id, anchor: UnitPoint(x: 0.5, y: 0.2))
                            }
                        }
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
        }
        // A tap on a word: its link, opened here as a lookup.
        .environment(\.openURL, OpenURLAction { url in
            guard let word = BookTranscriptLineRow.word(in: url) else { return .systemAction }
            HapticManager.shared.fireHaptic(.selection)
            onInteraction()
            lookup = LookupWord(term: word)
            return .handled
        })
        .sheet(item: $lookup) { word in
            DictionaryLookup(term: word.term)
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        }
    }

    /// How bright a line is: the one being read full, the rest dim.
    private func emphasis(of index: Int) -> Double {
        guard let current else { return 0.85 }
        return index == current ? 1 : 0.4
    }

    @ViewBuilder
    private func lineMenu(_ line: BookTranscript.Line) -> some View {
        Button("Play from Here", systemImage: "play") {
            onInteraction()
            isFollowing = true
            Task { await BookTranscriptLineRow.play(from: line.start) }
        }
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = line.text
        }
        ShareLink(item: line.text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        BookTranscriptTranslateButton(text: line.text)
    }
}

/// One line, its words links for a tap to look up. `emphasis` is how bright
/// it's drawn; `spoken`, on the line being read, how many of its words have
/// been said, those drawn bright and the rest dimmer (not on the Mac, where
/// text redrawn as it's read costs a burst of GPU memory). It's drawn again
/// only when one of those or the line changes.
private struct BookTranscriptLineRow: View, Equatable {
    let line: BookTranscript.Line
    let emphasis: Double
    let spoken: Int?
    let font: Font

    private static let scheme = "cue-lookup"

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line && lhs.emphasis == rhs.emphasis && lhs.spoken == rhs.spoken && lhs.font == rhs.font
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
        Text(Self.linked(line))
#else
        if let spoken {
            Self.words(line).textRenderer(SpokenWords(spoken: spoken))
        } else {
            Text(Self.linked(line))
        }
#endif
    }

    /// The line a word at a time, each tagged with its place, for
    /// `SpokenWords` to tell the said from the unsaid.
    private static func words(_ line: BookTranscript.Line) -> Text {
        var text = Text(verbatim: "")
        for index in line.words.indices {
            let word = Text(linked(line, only: index)).customAttribute(WordPlace(index: index))
            text = Text("\(text)\(word)")
        }
        return text
    }

    /// The line with each word a link to itself, its spacing and
    /// punctuation left out of the link; only word `only`, when given.
    private static func linked(_ line: BookTranscript.Line, only: Int? = nil) -> AttributedString {
        var text = AttributedString()
        for (index, word) in line.words.enumerated() where only == nil || only == index {
            var raw = word.text
            if index == 0 {
                raw = String(raw.drop { $0.isWhitespace })
            }
            let leading = raw.prefix { !$0.isLetter && !$0.isNumber }
            let rest = raw.dropFirst(leading.count)
            let core = rest.prefix { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-" }
            let trailing = rest.dropFirst(core.count)
            text.append(AttributedString(String(leading)))
            if !core.isEmpty {
                var linked = AttributedString(String(core))
                var components = URLComponents()
                components.scheme = scheme
                components.host = "word"
                components.queryItems = [URLQueryItem(name: "term", value: String(core))]
                linked.link = components.url
                text.append(linked)
            }
            text.append(AttributedString(String(trailing)))
        }
        return text
    }

    /// The word a tapped link stands for.
    static func word(in url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "term" }?.value
    }

    /// Plays from `fileTime` in the file playing: through the book player,
    /// so the place left joins the book's history.
    @MainActor
    static func play(from fileTime: TimeInterval) async {
        let controller = PlaybackRoute.shared.presented
        let player = AudiobookPlayer.shared
        guard let book = player.current, let part = book.partIndex(of: controller.nowPlayingDisplay) else { return }
        await player.jump(to: book.time(part: part, offset: max(fileTime - 0.3, 0)))
    }
}

/// A word's place in its line, on its run of text.
private struct WordPlace: TextAttribute {
    let index: Int
}

/// Draws the line being read with the word being said brightest, the words
/// said before it a little dimmer and the rest dimmer still. Changes only
/// as a word starts, not every frame.
private struct SpokenWords: TextRenderer {
    let spoken: Int

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                var copy = context
                let index = run[WordPlace.self]?.index ?? 0
                copy.opacity = index == spoken - 1 ? 1 : index < spoken ? 0.8 : 0.5
                copy.draw(run)
            }
        }
    }
}

// MARK: - Look Up and Translate

private struct LookupWord: Identifiable {
    let id = UUID()
    let term: String
}

/// The system dictionary's page for a word.
private struct DictionaryLookup: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

/// Translate in a line's menu, where the system's translation sheet is
/// available (not on the Mac, whose Catalyst build doesn't have it).
private struct BookTranscriptTranslateButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
#if canImport(Translation) && !os(visionOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 17.4, *) {
            Button("Translate", systemImage: "translate") {
                isPresented = true
            }
            .translationPresentation(isPresented: $isPresented, text: text)
        }
#endif
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

/// What the transcript is, for someone without Cue Super, and the way to it.
private struct BookTranscriptUpsell: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.quote")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text("Read Along")
                .font(.title2.bold())
            Text("See every word of the book as it's read, transcribed privately on this device. Tap a word to look it up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Get Cue Super") {
                FeatureGate.shared.presentPaywall(PaywallReason(feature: .bookTranscript))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 360)
    }
}
