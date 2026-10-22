import MusicSearchKit
import SwiftUI
import WatchKit
import WatchSync

/// Where a book's row goes: its page.
struct BookRoute: Hashable {
    let key: String
}

/// A book on the watch: how far in and what's left, Resume (or Play) with
/// the skips either side, its speed and chapters, and taking it off. It
/// reads the book again from its server as it opens, so a place another
/// player has moved it to since shows here (`WatchDownloadStore.refresh`).
struct BookScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchBookStore.self) private var books
    @Environment(\.dismiss) private var dismiss
    let key: String

    @State private var isChoosingSpeed = false

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
        return List {
            Section {
                header(pick, chapter: chapter)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction(position: position, duration: duration, finished: !isLoaded && progress?.isFinished == true))
                        .tint(.accentColor)
                    Text(statusText(isLoaded: isLoaded, progress: progress, position: position, duration: duration))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
                            VStack(alignment: .leading) {
                                Text(item.title)
                                    .lineLimit(2)
                                    .foregroundStyle(item.id == chapter?.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                Text(WatchBookFormat.length(item.duration))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!player.canPlayBook(pick, from: item.start))
                    }
                } header: {
                    Text("Chapters")
                }
            }

            Section {
                Button(role: .destructive) {
                    if isLoaded {
                        player.pause()
                    }
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
            .disabled(!isLoaded && !player.canPlayBook(pick))
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

    private func fraction(position: TimeInterval, duration: TimeInterval, finished: Bool) -> Double {
        if finished { return 1 }
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    private func statusText(isLoaded: Bool, progress: AudiobookProgress?, position: TimeInterval, duration: TimeInterval) -> String {
        guard isLoaded else {
            let status = WatchBookFormat.status(progress, duration: duration)
            guard progress?.isStarted != true, progress?.isFinished != true else { return status }
            return status.isEmpty ? "Not started" : "\(status) • Not started"
        }
        let left = max(duration - position, 0)
        return left < 60 ? "Under a minute left" : "\(WatchBookFormat.length(left)) left"
    }

    @ViewBuilder
    private func footer(files: [WatchSong], here: Int) -> some View {
        if files.isEmpty {
            if store.unreachable.contains(key) {
                Text("Couldn't reach the server. Cue tries again the next time you open it.")
            } else {
                Text("Looking up on the server…")
            }
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
        if here < songs.count {
            return songs.count == 1 ? "Downloading" : "\(here) of \(songs.count) files downloaded"
        }
        let duration = songs.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let status = WatchBookFormat.status(books.progress(for: pick.key), duration: duration)
        guard showsSize else { return status }
        return "\(status) • \(ByteCountFormatter.string(fromByteCount: store.bytesUsed(by: songs), countStyle: .file))"
    }
}
