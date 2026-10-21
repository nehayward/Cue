import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's page: its cover, the chapter the listener is in, Resume, and
/// its chapters or its place history, each of which plays the book from
/// there.
///
/// The book is read whole from its server when the page opens; where the
/// server has the listener is taken into `AudiobookProgressStore` (if it's
/// newer than this device's), so the page shows the newer of the two.
struct AudiobookDetailView: View {
    let book: PlayableContent

    @State private var audiobook: Audiobook?
    @State private var failed = false
    /// The list under the summary shows the book's place history rather
    /// than its chapters.
    @State private var showsHistory = false
    @State private var history = AudiobookPlaceHistory.shared
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared

    private var shown: PlayableContent { audiobook?.book ?? book }

    private var progress: AudiobookProgress? {
        store.progress(for: shown)
    }

    /// This book is the one loaded to play.
    private var isCurrent: Bool {
        player.current?.book.id == shown.id && player.current?.book.content.service == shown.content.service
    }

    /// The chapter the listener is in: the one playing while the player
    /// has the book, else the one its place falls in. Nil before it's
    /// started. From the chapter rather than the place, which moves every
    /// couple of seconds, so the page redraws only when the chapter changes.
    private var placeChapter: AudiobookChapter? {
        guard let audiobook else { return nil }
        if isCurrent { return player.currentChapter }
        guard let progress, progress.isStarted else { return nil }
        return audiobook.chapter(at: progress.position)
    }

    var body: some View {
        // A scroll view, not a List: a List resizes a row on its own, after
        // the row's content has changed, so the summary opening out jumped
        // however its text was animated.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if let audiobook, audiobook.chapters.count > 1 {
                        AudiobookPlaceChapter(audiobook: audiobook) { chapter in
                            withAnimation {
                                proxy.scrollTo(chapter.id, anchor: .center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    }
                    actions
                        .padding(.top, 20)

                    // The server didn't answer: under the book as it last
                    // read, a word that it's that; with nothing kept, why
                    // there's nothing.
                    if failed {
                        if audiobook == nil {
                            unreachableNotice
                                .padding(.top, 32)
                        } else {
                            Label("Couldn't reach \(book.content.service.title). This is the book as it last read.", systemImage: "wifi.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fontDesign(.rounded)
                                .padding(.top, 12)
                        }
                    }

                    if audiobook?.filesMissing == true {
                        missingFilesNotice
                            .padding(.top, 20)
                    }

                    if let summary = audiobook?.summary {
                        AudiobookSummary(text: summary)
                            .padding(.top, 20)
                    }

                    // Chapters, or where the listener has been. One chapter
                    // is the whole book, with nothing to choose between: its
                    // history alone, once it has one.
                    if let audiobook {
                        let hasChapters = audiobook.chapters.count > 1
                        if hasChapters || !history.places(for: shown).isEmpty {
                            Group {
                                if hasChapters {
                                    Picker("Show", selection: $showsHistory) {
                                        Text("Chapters").tag(false)
                                        Text("History").tag(true)
                                    }
                                    .pickerStyle(.segmented)
                                } else {
                                    Text("History")
                                        .font(.title3.bold())
                                }
                            }
                            .padding(.top, 28)
                            .padding(.bottom, 8)
                            if showsHistory || !hasChapters {
                                AudiobookHistoryList(book: shown, audiobook: audiobook)
                            } else {
                                let here = placeChapter
                                let isFinished = progress?.isFinished == true
                                ForEach(audiobook.chapters) { chapter in
                                    chapterRow(
                                        chapter,
                                        in: audiobook,
                                        isHere: chapter.id == here?.id,
                                        // Before the place, or all of a book finished.
                                        isDone: isFinished || here.map { chapter.start < $0.start } == true
                                    )
                                        .id(chapter.id)
                                    if chapter.id != audiobook.chapters.last?.id {
                                        Divider()
                                            .padding(.leading, 32)
                                    }
                                }
                            }
                        }
                    }

                    if audiobook == nil, !failed {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    finishedButton
                    OpenInServiceView(item: shown)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .disabled(audiobook == nil)
            }
        }
        // No pull to refresh: it's read afresh each time it opens, and in a
        // sheet (from the player) the pull is the sheet's, to dismiss it.
        .task {
            // The book as it last read, at once; the server's read replaces it.
            if audiobook == nil {
                audiobook = AudiobookLibrary.lastRead(of: book)
            }
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ContentArtworkView(content: shown, showMusicSource: false, preferredSize: ContentArtworkView.playerPreferredSize, cornerRadius: 8)
                // A fixed square: given only a width, the cover took the
                // row's height too and sat in a band of empty space.
                .frame(width: 260, height: 260)
                .overlay(alignment: .bottom) {
                    if let fraction = progress?.fraction, progress?.isStarted == true {
                        AudiobookProgressBar(fraction: fraction, tint: .white, isRounded: false)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(8)
                    }
                }
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                // New York, a book's own face, for its title. Nothing
                // around it may set a design: the outermost `.fontDesign`
                // wins over one nearer the text, so the lines under it set
                // rounded on themselves.
                Text(shown.title)
                    .font(.title3.bold())
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)
                Group {
                    // The author opens their page: their other books.
                    if !shown.subtitle.isEmpty {
                        NavigationLink(value: RouterDestination.artistDetail(content: shown, group: nil)) {
                            Text(shown.subtitle)
                                .font(.body)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows their books")
                    }
                    if let narrator = audiobook?.narrator {
                        Text("Narrated by \(narrator)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let detail = detailLine {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .fontDesign(.rounded)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    /// "12 hr, 5 min • 3 hr, 2 min left".
    private var detailLine: String? {
        guard let audiobook, audiobook.duration > 0 else { return nil }
        var parts = [AudiobookFormat.duration(audiobook.duration)]
        if let progress, let remaining = AudiobookFormat.remaining(progress) {
            parts.append(remaining)
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task { await player.play(shown) }
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                    } else {
                        Text("\(Image(systemName: "play.fill")) \(progress?.isStarted == true ? "Resume" : "Play")")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .glassButton()
            .foregroundStyle(.primary)

            if progress?.isStarted == true || progress?.isFinished == true {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await player.play(shown, from: 0) }
                } label: {
                    Text("\(Image(systemName: "backward.end.fill")) From Start")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .foregroundStyle(.primary)
            }

            // The whole book on this device, for listening with no network.
            ContainerDownloadButton(item: shown)
                .foregroundStyle(.primary)
        }
        .bold()
        .fontDesign(.rounded)
        .disabled(audiobook == nil || player.isLoading)
    }

    /// Nothing to show: the server didn't answer, and the book was never
    /// read on this device. Under the cover and the buttons, not over them.
    private var unreachableNotice: some View {
        ContentUnavailableView {
            Label("Couldn't Open This Book", systemImage: "book.closed")
        } description: {
            Text("Check that \(book.content.service.title) is reachable, then try again.")
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.bordered)
        }
    }

    /// The server lists the book but can't open its files, so it won't play
    /// and shows no chapters: said here, where the missing chapters show.
    private var missingFilesNotice: some View {
        let service = book.content.service.title
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(service) Can't Open This Book")
                    .font(.subheadline.bold())
                Text("\(service) lists its files but can't find them, so it won't play or show its chapters. Check that the files are still in the library's folder on the server, then scan the library again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var finishedButton: some View {
        if let audiobook {
            if progress?.isFinished == true {
                Button {
                    Task { await AudiobookLibrary.markFinished(audiobook, false) }
                } label: {
                    Label("Mark as Unfinished", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    Task { await AudiobookLibrary.markFinished(audiobook, true) }
                } label: {
                    Label("Mark as Finished", systemImage: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Chapters

    /// A chapter, playing the book from its start at a tap. `isHere` marks
    /// the one the listener is in, playing or not, and `isDone` those
    /// before it.
    private func chapterRow(_ chapter: AudiobookChapter, in audiobook: Audiobook, isHere: Bool, isDone: Bool) -> some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            Task {
                if isCurrent {
                    await player.play(chapter: chapter)
                } else {
                    await player.play(audiobook.book, from: chapter.start)
                }
            }
        } label: {
            AudiobookChapterRowLabel(chapter: chapter, isHere: isHere, isDone: isDone)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isHere ? .isSelected : [])
        .accessibilityValue(isDone ? "Listened" : "")
    }

    // MARK: - Loading

    private func load() async {
        failed = false
        guard let loaded = await AudiobookLibrary.load(book) else {
            failed = true
            return
        }
        store.recordServerProgress(of: loaded)
        audiobook = loaded
    }
}

/// The chapter the listener is in, under the book's title, with what's
/// left of it: a tap plays the book from where it was left, or, while it
/// plays, brings the chapter into view in the list below (`reveal`). It
/// reads the book's place, which moves every couple of seconds while it
/// plays, so it's a view of its own: the page around it doesn't redraw
/// with it. Nothing before the book is started.
private struct AudiobookPlaceChapter: View {
    let audiobook: Audiobook
    let reveal: (AudiobookChapter) -> Void

    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared

    private var route: PlaybackRoute { .shared }

    /// The player has this book, playing or paused.
    private var isLoaded: Bool {
        player.current?.book.isSameBook(as: audiobook.book) == true && player.isPlayingBook(on: route.presented)
    }

    /// The chapter, and where in the book: the player's while it has the
    /// book, else the place kept for it.
    private var place: (chapter: AudiobookChapter, position: TimeInterval)? {
        if player.current?.book.isSameBook(as: audiobook.book) == true, let chapter = player.currentChapter {
            return (chapter, player.position)
        }
        guard let progress = store.progress(for: audiobook.book), progress.isStarted,
              let chapter = audiobook.chapter(at: progress.position) else { return nil }
        return (chapter, progress.position)
    }

    var body: some View {
        if let place {
            let isPlaying = isLoaded && route.presented.isPlaying
            // At the speed it plays, as the player says it, once loaded.
            let left = isLoaded
                ? player.timeLeftText(compact: true) ?? ""
                : "\(AudiobookFormat.duration(max(place.chapter.end - place.position, 0))) left"
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                if isPlaying {
                    reveal(place.chapter)
                    return
                }
                Task {
                    if isLoaded {
                        await route.presented.togglePlayback()
                    } else {
                        await player.play(audiobook.book)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(place.chapter.title)
                        .lineLimit(1)
                    Text("· \(left)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(.tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.14), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading)
            .accessibilityLabel("\(place.chapter.title), \(left)")
            .accessibilityHint(isPlaying ? "Shows the chapter in the list" : "Plays from where you left off")
        }
    }
}

/// A book's description: four lines, the last fading out, opening out to
/// the whole of it at a tap anywhere on it, and closing again the same way.
/// The text is laid out whole either way and only the frame showing it
/// grows, so it opens as one smooth reveal rather than jumping from one
/// layout of the text to another (a changing `lineLimit` re-wraps it
/// mid-animation); as a geometry group it reaches the page as a single
/// change of size, which the rows below follow in step.
struct AudiobookSummary: View {
    let text: String

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private static let collapsedLines = 4

    private var isMeasured: Bool { fullHeight > 0 && collapsedHeight > 0 }
    private var truncates: Bool { fullHeight > collapsedHeight + 1 }
    private var isCollapsed: Bool { truncates && !isExpanded }

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: isMeasured ? (isCollapsed ? collapsedHeight : fullHeight) : 0, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            // The last line fading out says there's more.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: isCollapsed ? 24 : 0)
                }
            }
            .background(alignment: .top) { measurements }
            .opacity(isMeasured ? 1 : 0)
            .geometryGroup()
            .font(.callout)
            // New York, a reading face at this size.
            .fontDesign(.serif)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: isExpanded ? "Show Less" : "Show More", toggle)
    }

    private func toggle() {
        guard truncates else { return }
        HapticManager.shared.fireHaptic(.selection)
        withAnimation(.smooth(duration: 0.45)) {
            isExpanded.toggle()
        }
    }

    /// The text's whole height and its first four lines' at the width it's
    /// shown at, from hidden copies of it.
    private var measurements: some View {
        ZStack(alignment: .top) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            Text(text)
                .lineLimit(Self.collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
        }
        .hidden()
    }
}
