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
    }
}

/// A button for each of the loaded book's chapters, jumping to it; the
/// one playing is marked.
struct AudiobookChapterButtons: View {
    let chapters: [AudiobookChapter]

    @State private var player = AudiobookPlayer.shared

    var body: some View {
        ForEach(chapters) { chapter in
            Button {
                HapticManager.shared.fireHaptic(.selection)
                Task { await player.jump(to: chapter.start) }
            } label: {
                // Marked as the book's page marks it.
                if chapter.id == player.currentChapter?.id {
                    Label(chapter.title, systemImage: "bookmark.fill")
                } else {
                    Text(chapter.title)
                }
            }
        }
    }
}

/// The player's origin line while a book with chapters plays: the chapter
/// playing, in the caption slot the album or playlist has for a song, and
/// a tap opens the chapters, with Previous and Next Chapter over them. It
/// reads the book's place, which moves every couple of seconds, so it's a
/// view of its own: the player around it doesn't redraw with it.
struct AudiobookChapterLine: View {
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        Menu {
            if let book = player.current {
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
                AudiobookChapterButtons(chapters: book.chapters)
            }
        } label: {
            HStack(spacing: 3) {
                Text(player.currentChapter?.title ?? "")
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption.smallCaps())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter: \(player.currentChapter?.title ?? "")")
    }
}

/// The player menu's book items while a book plays: its chapters, to jump
/// to, and on this device its speed (a speaker has only 1×).
struct AudiobookPlayerMenuItems: View {
    let isOnDevice: Bool

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
                Menu {
                    AudiobookChapterButtons(chapters: book.chapters)
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
