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

    /// The book as its server read it as the page opened.
    @State private var loaded: Audiobook?
    @State private var failed = false
    /// Which list is under the summary: the book's chapters, its
    /// bookmarks or its place history.
    @State private var list = BookList.chapters
    @State private var history = AudiobookPlaceHistory.shared
    @State private var bookmarks = AudiobookBookmarks.shared
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared

    /// The book as the server read it, else as it last read, which is there
    /// from the first frame: the page opens whole rather than filling in.
    private var audiobook: Audiobook? {
        loaded ?? AudiobookLibrary.lastRead(of: book)
    }

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

                    // Chapters, bookmarks, or where the listener has been.
                    // One chapter is the whole book, with nothing to choose
                    // between: its bookmarks and history alone, once it has
                    // them.
                    if let audiobook {
                        let lists = lists(for: audiobook)
                        if let shownList = lists.contains(list) ? list : lists.first {
                            VStack(alignment: .leading) {
                                if lists.count > 1 {
                                    Picker("Show", selection: Binding(get: { shownList }, set: { list = $0 })) {
                                        ForEach(lists, id: \.self) { kind in
                                            Text(kind.title).tag(kind)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                } else {
                                    Text(shownList.title)
                                        .font(.title3.bold())
                                }
                            }
                            .padding(.top, 28)
                            .padding(.bottom, 8)
                            switch shownList {
                            case .history:
                                AudiobookHistoryList(book: shown, audiobook: audiobook)
                            case .bookmarks:
                                AudiobookBookmarkList(book: shown, audiobook: audiobook)
                            case .chapters:
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
                                    // None against the listener's chapter,
                                    // which its fill sets apart.
                                    if chapter.id != audiobook.chapters.last?.id, chapter.id != here?.id, audiobook.chapters.after(chapter)?.id != here?.id {
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
                    WatchMenuSection(item: shown)
                    OpenInServiceView(item: shown)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .disabled(audiobook == nil)
            }
        }
        // No pull to refresh: it's read afresh each time it opens, and in a
        // sheet (from the player) the pull is the sheet's, to dismiss it.
        .task { await load() }
        // Who reads a Plex book, from Audible, if it isn't known yet.
        .onAppear { AudiobookDetails.shared.request([book]) }
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
                // The author opens their page: their other books. An
                // episode's podcast opens the podcast's.
                if !shown.subtitle.isEmpty {
                    NavigationLink(value: authorDestination) {
                        Text(shown.subtitle)
                            .font(.body)
                            .fontDesign(.rounded)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(shown.isPodcastEpisode ? "Shows its episodes" : "Shows their books")
                }
                // Audiobookshelf's, else Audible's for a Plex book.
                if let narrator = audiobook?.narrator ?? AudiobookDetails.shared.narrator(for: shown) {
                    Text("Narrated by \(narrator)")
                        .font(.footnote)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
                if let detail = detailLine {
                    Text(detail)
                        .font(.footnote)
                        .fontDesign(.rounded)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    /// The lists under the summary.
    enum BookList: Hashable, CaseIterable {
        case chapters
        case bookmarks
        case history

        var title: String {
            switch self {
            case .chapters: "Chapters"
            case .bookmarks: "Bookmarks"
            case .history: "History"
            }
        }
    }

    /// The lists the book has something for: chapters for one with more
    /// than one, bookmarks once it has some (or while it's loaded to play,
    /// to make the first), history once it has been played.
    private func lists(for audiobook: Audiobook) -> [BookList] {
        BookList.allCases.filter { kind in
            switch kind {
            case .chapters: audiobook.chapters.count > 1
            case .bookmarks: !bookmarks.bookmarks(for: shown).isEmpty || player.isLoaded(shown)
            case .history: !history.places(for: shown).isEmpty
            }
        }
    }

    /// Where the line under the title goes: the author's page, or for an
    /// episode its podcast's.
    private var authorDestination: RouterDestination {
        if let podcastID = shown.podcastID {
            return .audiobookshelfPodcast(AudiobookshelfPodcast(id: podcastID, title: shown.subtitle))
        }
        return .artistDetail(content: shown, group: nil)
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
        let isLoaded = player.isLoaded(shown)
        let isPlaying = isLoaded && PlaybackRoute.shared.presented.isPlaying
        return HStack(spacing: 12) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                if isLoaded {
                    Task { await PlaybackRoute.shared.presented.togglePlayback() }
                } else {
                    Task { await player.play(shown) }
                }
            } label: {
                VStack {
                    if player.isLoading {
                        ProgressView()
                    } else {
                        Text("\(Image(systemName: isPlaying ? "pause.fill" : "play.fill")) \(isPlaying ? "Pause" : progress?.isStarted == true ? "Resume" : "Play")")
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
            Task { await player.pick(audiobook.book, at: chapter.start, in: audiobook) }
        } label: {
            AudiobookChapterRowLabel(chapter: chapter, isHere: isHere, isDone: isDone, book: audiobook.book)
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
        self.loaded = loaded
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
        player.isLoaded(audiobook.book)
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
