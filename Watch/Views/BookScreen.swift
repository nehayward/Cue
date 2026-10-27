import MusicSearchKit
import SwiftUI
import WatchKit
import WatchSync

/// Where a book's row goes: its page.
struct BookRoute: Hashable {
    let key: String
}

/// A book on the watch: how far in and what's left (the chapter's while
/// it's in one, moved with the Digital Crown from a tap while it's loaded),
/// Resume (or Play) with the skips either side, its speed and chapters,
/// and taking it off. It
/// reads the book again from its server as it opens, so a place another
/// player has moved it to since shows here (`WatchDownloadStore.refresh`).
struct BookScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchBookStore.self) private var books
    @Environment(\.dismiss) private var dismiss
    let key: String

    @State private var isChoosingSpeed = false
    @State private var isChoosingSleep = false
    @State private var isScrubbing = false

    var body: some View {
        if let pick = store.picks.pick(key: key) {
            content(for: pick)
                .navigationTitle(pick.title)
                .task {
                    store.refresh(pick)
                }
                .sheet(isPresented: $isChoosingSpeed) {
                    SpeedPicker(current: books.rate(for: key)) { rate in
                        isChoosingSpeed = false
                        player.setRate(rate, for: pick)
                    }
                }
                .sheet(isPresented: $isChoosingSleep) {
                    SleepTimerPicker(current: player.sleepTimer) { timer in
                        isChoosingSleep = false
                        player.setSleepTimer(timer)
                    }
                }
                .sheet(isPresented: $isScrubbing) {
                    ChapterScrubScreen(key: key)
                }
        } else {
            Text("Removed from this watch")
                .foregroundStyle(.secondary)
        }
    }

    private func content(for pick: WatchPick) -> some View {
        let files = store.songs(in: [key])
        let here = files.filter { store.isDownloaded($0.key) }.count
        let duration = files.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let isLoaded = player.book?.key == key
        let progress = books.progress(for: key)
        let position = isLoaded ? player.bookPosition : progress?.position ?? 0
        let chapters = books.chapters(for: key)
        let chapter = chapters.chapter(at: position)
        let isStarted = isLoaded || progress?.isStarted == true || progress?.isFinished == true
        let isFinished = !isLoaded && progress?.isFinished == true
        return List {
            Section {
                header(pick, chapter: chapter)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                // While it's the book loaded, a tap moves it with the
                // Digital Crown.
                Group {
                    let place = BookPlaceSummary(chapters: chapters, duration: duration, isLoaded: isLoaded, progress: progress)
                    if isLoaded {
                        Button {
                            isScrubbing = true
                        } label: {
                            place
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Move in the chapter with the Digital Crown")
                    } else {
                        place
                    }
                }
                .listRowBackground(Color.clear)

                transport(pick, isLoaded: isLoaded, isStarted: isStarted)
                    .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    isChoosingSpeed = true
                } label: {
                    LabeledContent("Speed", value: WatchBookFormat.rate(books.rate(for: key)))
                }
                // While it's the book loaded: the timer is the player's.
                if isLoaded {
                    Button {
                        isChoosingSleep = true
                    } label: {
                        LabeledContent("Sleep Timer") {
                            SleepTimerValue(timer: player.sleepTimer)
                        }
                    }
                }
                if isStarted {
                    Button {
                        play(pick, from: 0)
                    } label: {
                        Label("Play from Start", systemImage: "backward.end.fill")
                    }
                    .disabled(!player.canPlayBook(pick, from: 0))
                }
            }

            if !chapters.isEmpty {
                Section {
                    ForEach(chapters) { item in
                        Button {
                            play(pick, from: item.start)
                        } label: {
                            BookChapterRow(
                                chapter: item,
                                isHere: isStarted && !isFinished && item.id == chapter?.id,
                                isDone: isFinished || chapter.map { item.start < $0.start } == true,
                                isLoaded: isLoaded,
                                keptPosition: position
                            )
                        }
                        .disabled(!player.canPlayBook(pick, from: item.start))
                    }
                } header: {
                    Text("Chapters")
                }
            }

            Section {
                Button(role: .destructive) {
                    // Playing, it stops first (`WatchPlayer.picksDidChange`).
                    store.remove(key: key)
                    dismiss()
                } label: {
                    Text("Remove from Watch")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                footer(files: files, here: here)
            }
        }
        // Once its files are all here, they're read for chapters its
        // server didn't give.
        .task(id: here == files.count) {
            books.readChaptersIfNeeded(for: key)
        }
    }

    private func header(_ pick: WatchPick, chapter: AudiobookChapter?) -> some View {
        VStack(spacing: 4) {
            ArtworkView(url: pick.artworkURL, symbol: "book.closed")
                .frame(width: 80, height: 80)
            Text(pick.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if !pick.subtitle.isEmpty {
                Text(pick.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let chapter {
                Text(chapter.title)
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
        }
    }

    /// Back 15 s, play or pause, ahead 30 s. Play is the screen's primary
    /// action, so double tap presses it.
    private func transport(_ pick: WatchPick, isLoaded: Bool, isStarted: Bool) -> some View {
        let isPlaying = isLoaded && player.isPlaying
        return HStack {
            Button {
                player.skip(by: -WatchPlayer.skipBack)
            } label: {
                Image(systemName: "gobackward.15")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Back 15 Seconds")
            .disabled(!isLoaded)
            Button {
                if isLoaded {
                    player.togglePlayPause()
                } else {
                    play(pick, from: nil)
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(isPlaying ? "Pause" : isStarted ? "Resume" : "Play")
            .primaryHandGesture()
            // Its place in a part not on the watch yet: nothing to play.
            .disabled(!isPlaying && !player.canPlayBook(pick))
            Button {
                player.skip(by: WatchPlayer.skipAhead)
            } label: {
                Image(systemName: "goforward.30")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Ahead 30 Seconds")
            .disabled(!isLoaded)
        }
        .buttonStyle(.bordered)
    }

    private func play(_ pick: WatchPick, from time: TimeInterval?) {
        if !player.playBook(pick, from: time) {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    @ViewBuilder
    private func footer(files: [WatchSong], here: Int) -> some View {
        if files.isEmpty {
            if store.unreachable.contains(key) {
                Text("Couldn't reach the server. Cue tries again the next time you open it.")
            } else {
                Text("Looking up on the server…")
            }
        } else if here < files.count, store.isHeldBack(book: key) {
            Text("Books download with Cue Super. Get it in Cue on your iPhone.")
        } else if here < files.count {
            Text(files.count == 1
                ? "Downloading. Fast Download gets it here sooner."
                : "\(here) of \(files.count) files on this watch. Fast Download gets the rest here sooner.")
        } else {
            Text("\(WatchDownloadStore.countText(files.count, files: true)) • \(ByteCountFormatter.string(fromByteCount: store.bytesUsed(by: files), countStyle: .file))")
        }
    }
}

/// A book's speed, as on the iPhone.
struct SpeedPicker: View {
    let current: Double
    let choose: (Double) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(WatchBookStore.rateChoices, id: \.self) { rate in
                    Button {
                        choose(rate)
                    } label: {
                        HStack {
                            Text(WatchBookFormat.rate(rate))
                            Spacer(minLength: 0)
                            if rate == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Speed")
        }
    }
}

/// How long the sleep timer has left, counting down, or End of Chapter.
private struct SleepTimerValue: View {
    let timer: WatchPlayer.SleepTimer?

    var body: some View {
        switch timer {
        case let .at(date):
            Text(date, style: .timer)
                .monospacedDigit()
        case .endOfChapter:
            Text("End of Chapter")
        case nil:
            Text("Off")
        }
    }
}

/// The sleep timer's choices: off, the end of the chapter, or a while.
struct SleepTimerPicker: View {
    let current: WatchPlayer.SleepTimer?
    let choose: (WatchPlayer.SleepTimer?) -> Void

    var body: some View {
        NavigationStack {
            List {
                row("Off", isOn: current == nil) { choose(nil) }
                row("End of Chapter", isOn: current == .endOfChapter) { choose(.endOfChapter) }
                ForEach(WatchPlayer.sleepChoices, id: \.self) { minutes in
                    row("\(minutes) min", isOn: false) {
                        choose(.at(.now.addingTimeInterval(TimeInterval(minutes * 60))))
                    }
                }
            }
            .navigationTitle("Sleep Timer")
        }
    }

    private func row(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

/// A book on the watch, with what's left of it or how far its download
/// has got — and, in Downloads, the room it takes.
struct BookRow: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchBookStore.self) private var books
    let pick: WatchPick
    var showsSize = false

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: pick.artworkURL, symbol: "book.closed")
                .frame(width: 36, height: 36)
            VStack(alignment: .leading) {
                Text(pick.title)
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
    }

    private var detail: String {
        guard let songs = store.songsByPick[pick.key] else {
            return store.unreachable.contains(pick.key) ? "Can't reach the server" : "Looking up…"
        }
        let here = songs.filter { store.isDownloaded($0.key) }.count
        if here < songs.count, store.isHeldBack(book: pick.key) {
            return "Needs Cue Super"
        }
        if here < songs.count {
            return songs.count == 1 ? "Downloading" : "\(here) of \(songs.count) files downloaded"
        }
        let duration = songs.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let status = WatchBookFormat.status(books.progress(for: pick.key), duration: duration)
        guard showsSize else { return status }
        return "\(status) • \(ByteCountFormatter.string(fromByteCount: store.bytesUsed(by: songs), countStyle: .file))"
    }
}
