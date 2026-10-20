import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A slim listening-progress bar for a book: its rows, its cover and its
/// page. From Clic's Audible screens.
struct AudiobookProgressBar: View {
    let fraction: Double
    var height: Double = 3
    var tint: Color = .accentColor
    /// Rounded ends, or square ones (on a cover's hard edge).
    var isRounded: Bool = true

    /// Read with `onGeometryChange` rather than a `GeometryReader`, which
    /// re-runs its content on every layout pass.
    @State private var width: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isRounded ? height / 2 : 0)
        shape
            .fill(.secondary.opacity(0.35))
            .overlay(alignment: .leading) {
                shape
                    .fill(tint)
                    .frame(width: width * min(max(fraction, 0), 1))
            }
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement()
            .accessibilityLabel("Listening progress")
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

enum AudiobookFormat {
    /// "5h 3m", "42m": how long, to the minute, in the narrow form.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), seconds > 0 ? 1 : 0)
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// What the listener has left, or that they've finished.
    static func remaining(_ progress: AudiobookProgress) -> String? {
        if progress.isFinished { return "Finished" }
        guard progress.isStarted, progress.duration > 0 else { return nil }
        return "\(duration(progress.remaining)) left"
    }

    /// "1:02:15" for a place in a book.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

extension PlayableContent {
    /// The book with what's left of it added to its subtitle ("Andy Weir •
    /// 5 hr, 3 min left"), for a shelf's rows.
    func withAudiobookProgress(_ progress: AudiobookProgress?) -> PlayableContent {
        guard let progress, let remaining = AudiobookFormat.remaining(progress) else { return self }
        let subtitle = [subtitle, remaining].filter { !$0.isEmpty }.joined(separator: " • ")
        return PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            artwork: artwork,
            content: content,
            previewURL: previewURL,
            metadata: metadata
        )
    }
}

/// A book's row: the shelf's ordinary row, with how much is left under the
/// author and a thin progress line under the text. Reads only its own
/// book's progress.
struct AudiobookRow: View {
    let book: PlayableContent

    var body: some View {
        let progress = AudiobookProgressStore.shared.progress(for: book)
        let isListened = progress?.isStarted == true || progress?.isFinished == true
        PlayableContentView(item: book.withAudiobookProgress(progress), progress: isListened ? progress?.fraction : nil)
    }
}

/// A book's long-press menu: Resume (or Play), from the start, and
/// finished or not. A book plays from where it was left, never into the
/// queue, so there are none of the queue's positions.
struct AudiobookMenuItems: View {
    let book: PlayableContent

    var body: some View {
        let progress = AudiobookProgressStore.shared.progress(for: book)
        Button {
            Task { await AudiobookPlayer.shared.play(book) }
        } label: {
            if progress?.isStarted == true {
                Label("Resume", systemImage: "play.fill")
            } else {
                Label("Play", systemImage: "play.fill")
            }
        }
        if progress?.isStarted == true || progress?.isFinished == true {
            Button {
                Task { await AudiobookPlayer.shared.play(book, from: 0) }
            } label: {
                Label("Play from Start", systemImage: "backward.end.fill")
            }
        }
        NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
            Label("View Book", systemImage: "book")
        }
        Section {
            AudiobookDownloadMenuItems(book: book)
        }
    }
}

/// The whole book on this device, from a menu: Download Book, or Remove
/// (Cancel while it comes down). At a glance rather than the progress: an
/// open menu redrawn with every bit of progress flickers.
struct AudiobookDownloadMenuItems: View {
    let book: PlayableContent

    @Environment(AlertService.self) private var alertService

    var body: some View {
        let manager = DownloadManager.shared
        if manager.canDownload(contentsOf: book) {
            switch manager.containerPresence(for: book) {
            case .downloaded:
                Button(role: .destructive) {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    manager.removeDownload(contentsOf: book)
                    alertService.showAlertContent(with: book, subtitle: "Removed from this device", symbolName: "trash")
                } label: {
                    Label("Remove Download", systemImage: "trash")
                }
            case .downloading:
                Button(role: .destructive) {
                    manager.removeDownload(contentsOf: book)
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            case nil:
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    guard FeatureGate.shared.unlock(.downloads) else { return }
                    Task { @MainActor in
                        await LocalDownloadMenuSection.download(book, alertService: alertService)
                    }
                } label: {
                    Label("Download Book", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}

extension AudiobookPlayer {
    /// Plays the loaded book from `chapter`'s start.
    func play(chapter: AudiobookChapter) async {
        await playLoaded(from: chapter.start)
    }

    /// Plays the loaded book from book time `time`: a chapter or a place
    /// picked is meant to be heard, so a paused book starts there, where a
    /// skip leaves it paused. A move to another file starts playing by
    /// itself; a seek within the file playing doesn't.
    func playLoaded(from time: TimeInterval) async {
        guard let current else { return }
        let controller = PlaybackRoute.shared.controller
        let wasPlaying = controller.isPlaying
        let staysInFile = current.partIndex(of: controller.nowPlayingDisplay) == current.timeline.location(at: time).part
        await jump(to: time)
        if !wasPlaying, staysInFile {
            await controller.togglePlayback()
        }
    }

    /// Plays `book` from book time `time`: the loaded one from there, any
    /// other read from its server and started there.
    func play(_ book: PlayableContent, at time: TimeInterval) async {
        if current?.book.isSameBook(as: book) == true {
            await playLoaded(from: time)
        } else {
            await play(book, from: time)
        }
    }
}

/// A book's place history (`AudiobookPlaceHistory`), newest first: what
/// happened where, when, and in which chapter. A tap plays from there, and
/// the place left for it joins the list, so going back is never a loss.
struct AudiobookHistoryList: View {
    let book: PlayableContent
    /// The book read whole, for its chapters' names; nil before it's read.
    let audiobook: Audiobook?
    /// After a place is picked: the sheet showing the list closes.
    var onPick: () -> Void = {}

    @State private var history = AudiobookPlaceHistory.shared

    var body: some View {
        let places = history.places(for: book)
        if places.isEmpty {
            ContentUnavailableView {
                Label("No History Yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Where you start, pause and jump from in this book shows here, so you can always go back.")
            }
            .padding(.top, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(places) { place in
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        onPick()
                        Task { await AudiobookPlayer.shared.play(book, at: place.position) }
                    } label: {
                        row(place)
                    }
                    .buttonStyle(.plain)
                    if place.id != places.last?.id {
                        Divider()
                            .padding(.leading, 32)
                    }
                }
            }
        }
    }

    private func row(_ place: AudiobookPlaceHistory.Place) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(place.kind))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(place.kind))
                    .foregroundStyle(.primary)
                Text([audiobook?.chapter(at: place.position)?.title, AudiobookFormat.clock(place.position)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer()
            Text(Self.when(place.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays from here")
    }

    private static func title(_ kind: AudiobookPlaceHistory.Place.Kind) -> LocalizedStringKey {
        switch kind {
        case .started: "Started"
        case .paused: "Paused"
        case .jumpedFrom: "Moved away from here"
        case .replaced: "Before another device's place"
        case .left: "Left the book"
        }
    }

    private static func symbol(_ kind: AudiobookPlaceHistory.Place.Kind) -> String {
        switch kind {
        case .started: "play.fill"
        case .paused: "pause.fill"
        case .jumpedFrom: "arrow.uturn.backward"
        case .replaced: "iphone.and.arrow.forward"
        case .left: "rectangle.portrait.and.arrow.right"
        }
    }

    /// "2:41 PM" today, "Mon 2:41 PM" this week, "Oct 12" before.
    private static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A chapter's row: a bookmark, its title, where it starts and how long it
/// runs. `isHere` marks the listener's chapter, in the accent. The book's
/// page and the chapters sheet both list them so.
struct AudiobookChapterRowLabel: View {
    let chapter: AudiobookChapter
    let isHere: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isHere ? "bookmark.fill" : "bookmark")
                .foregroundStyle(isHere ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .foregroundStyle(.primary)
                    .fontWeight(isHere ? .semibold : .regular)
                Text(AudiobookFormat.clock(chapter.start))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(AudiobookFormat.duration(chapter.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // The listener's chapter is the accent throughout: its levels
        // (primary, secondary) are the accent's.
        .foregroundStyle(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground))
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// The loaded book's chapters, as a sheet from the player's chapter line
/// and its menu: a long book's were a menu taller than the screen. It opens
/// on the chapter playing and follows it; a chapter picked plays from its
/// start and the sheet goes. Previous and Next Chapter sit under the list
/// and leave it open. Its other tab is the book's place history.
struct AudiobookChaptersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = AudiobookPlayer.shared
    @State private var showsHistory = false

    var body: some View {
        let chapters = player.current?.chapters ?? []
        NavigationStack {
            Group {
                if showsHistory, let book = player.current {
                    ScrollView {
                        AudiobookHistoryList(book: book.book, audiobook: book) { dismiss() }
                            .padding(.horizontal, 20)
                    }
                } else {
                    chapterList(chapters)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !showsHistory {
                    chapterButtons
                }
            }
            .navigationTitle(showsHistory ? "History" : "Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $showsHistory) {
                        Text("Chapters").tag(false)
                        Text("History").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "xmark")
                    }
                }
            }
        }
        .fontDesign(.rounded)
    }

    private func chapterList(_ chapters: [AudiobookChapter]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { chapter in
                        let isHere = chapter.id == player.currentChapter?.id
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            dismiss()
                            Task { await player.play(chapter: chapter) }
                        } label: {
                            AudiobookChapterRowLabel(chapter: chapter, isHere: isHere)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isHere ? .isSelected : [])
                        .id(chapter.id)
                        if chapter.id != chapters.last?.id {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                guard let playing = player.currentChapter else { return }
                proxy.scrollTo(playing.id, anchor: .center)
            }
            .onChange(of: player.currentChapter?.id) { _, playing in
                guard let playing else { return }
                withAnimation {
                    proxy.scrollTo(playing, anchor: .center)
                }
            }
        }
    }

    private var chapterButtons: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                Task { await player.skipToPreviousChapter() }
            } label: {
                Label("Previous", systemImage: "backward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            Button {
                HapticManager.shared.fireHaptic(.selection)
                Task { await player.skipToNextChapter() }
            } label: {
                Label("Next", systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(player.nextChapter == nil)
        }
        .glassButton()
        .foregroundStyle(.primary)
        .bold()
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

/// What's left of the chapter playing, "33m left in chapter", or of the
/// whole book, "14h 24m left in book", after `prefix` (the author, or the
/// speaker) when there is one: the player's middle line for a book, in the
/// audio quality's place, and the mini player's line under the title. A
/// tap on the player's switches the two, for the mini player's too. It
/// reads the book's place, which moves every couple of seconds, so it's a
/// view of its own: the player around it doesn't redraw with it.
struct AudiobookTimeLeft: View {
    var prefix: String? = nil
    /// "33m left", for a narrow line (the mini player's), which leaves a
    /// tap to the mini player.
    var isCompact = false

    @State private var player = AudiobookPlayer.shared
    @AppStorage(AppStorageKeys.audiobookTimeLeftShowsBook) private var showsBook = false

    var body: some View {
        let left = player.timeLeftText(ofBook: showsBook, compact: isCompact)
        let parts = [prefix.flatMap { $0.isEmpty ? nil : $0 }, left].compactMap { $0 }
        let line = Text(parts.joined(separator: " • "))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.default, value: left)
        if !isCompact, player.hasChapters {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                showsBook.toggle()
            } label: {
                line
                    // A caption is a small target: take a little more
                    // around it, short of the scrubber above.
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsBook ? "Shows the time left in the chapter" : "Shows the time left in the book")
        } else {
            line
        }
    }
}

/// The player's origin line while a book with chapters plays: the chapter
/// playing, in the caption slot the album or playlist has for a song, and
/// a tap opens the chapters sheet (`AudiobookChaptersSheet`). It reads the
/// chapter, which changes only at a chapter's end, so it's a view of its
/// own: the player around it doesn't redraw with it.
struct AudiobookChapterLine: View {
    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            router.sheet(to: .audiobookChapters)
        } label: {
            Text(player.currentChapter?.title ?? "")
            .font(.caption.smallCaps())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter: \(player.currentChapter?.title ?? "")")
        .accessibilityHint("Shows the chapters")
    }
}

/// The player menu's book items while a book plays: Previous and Next
/// Chapter, the chapters sheet, and on this device its speed (a speaker has
/// only 1×).
struct AudiobookPlayerMenuItems: View {
    let isOnDevice: Bool

    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        if let book = player.current {
            if book.chapters.count > 1 {
                ControlGroup {
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        Task { await player.skipToPreviousChapter() }
                    } label: {
                        Label("Previous Chapter", systemImage: "backward.end.fill")
                    }
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        Task { await player.skipToNextChapter() }
                    } label: {
                        Label("Next Chapter", systemImage: "forward.end.fill")
                    }
                    .disabled(player.nextChapter == nil)
                }
                Button {
                    router.sheet(to: .audiobookChapters)
                } label: {
                    Label(player.currentChapter?.title ?? "Chapters", systemImage: "list.bullet")
                }
            }
            if isOnDevice {
                Picker(selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(AudiobookPlayer.rates, id: \.self) { rate in
                        Text(Self.label(for: rate)).tag(rate)
                    }
                } label: {
                    Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                    Text(Self.label(for: player.rate))
                }
                .pickerStyle(.menu)
            }
        }
    }

    /// "1.25×".
    static func label(for rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}
