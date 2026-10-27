import MusicSearchKit
import SwiftUI
import WatchKit

/// The book's place on its page. Started and in a chapter: the chapter's
/// bar with the time into it and what's left of it either side, and the
/// book's time left under them, as Apple Books has it. Otherwise the whole
/// book's bar. Drawn from the player's clock while it plays, once a second
/// (`WatchPlayer.livePosition`), so it's where the book is now rather than
/// its last kept place.
struct BookPlaceSummary: View {
    @Environment(WatchPlayer.self) private var player
    let chapters: [AudiobookChapter]
    let duration: TimeInterval
    let isLoaded: Bool
    let progress: AudiobookProgress?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !(isLoaded && player.isPlaying))) { _ in
            content(at: isLoaded ? player.livePosition : progress?.position ?? 0)
        }
    }

    @ViewBuilder
    private func content(at position: TimeInterval) -> some View {
        let isFinished = !isLoaded && progress?.isFinished == true
        let isStarted = isLoaded || progress?.isStarted == true
        VStack(alignment: .leading, spacing: 4) {
            if isStarted, !isFinished, chapters.count > 1, let chapter = chapters.chapter(at: position) {
                let into = min(max(position - chapter.start, 0), chapter.duration)
                ProgressView(value: chapter.duration > 0 ? into / chapter.duration : 0)
                    .tint(.accentColor)
                HStack {
                    Text(WatchBookFormat.clock(into))
                    Spacer(minLength: 4)
                    Text("−\(WatchBookFormat.clock(chapter.duration - into))")
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                Text("\(WatchBookFormat.left(max(duration - position, 0))) in book")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView(value: isFinished ? 1 : duration > 0 ? min(max(position / duration, 0), 1) : 0)
                    .tint(.accentColor)
                Text(status(at: position))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func status(at position: TimeInterval) -> String {
        guard isLoaded else {
            let status = WatchBookFormat.status(progress, duration: duration)
            guard progress?.isStarted != true, progress?.isFinished != true else { return status }
            return status.isEmpty ? "Not started" : "\(status) • Not started"
        }
        return WatchBookFormat.left(max(duration - position, 0))
    }
}

/// A chapter in a book's list: its title, where it starts and how long it
/// runs. The listener's chapter is in the accent with a bar of how far
/// it's been heard and what's left of it, moving while it plays; the ones
/// before it are dimmed, so the list reads as how far the book has got.
struct BookChapterRow: View {
    let chapter: AudiobookChapter
    let isHere: Bool
    let isDone: Bool
    let isLoaded: Bool
    /// The book's kept place, for a chapter here while the player hasn't
    /// the book.
    let keptPosition: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chapter.title)
                .lineLimit(2)
                .foregroundStyle(isHere ? AnyShapeStyle(.tint) : isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            if isHere {
                ChapterHereProgress(chapter: chapter, isLoaded: isLoaded, keptPosition: keptPosition)
            } else {
                Text("\(WatchBookFormat.clock(chapter.start)) · \(WatchBookFormat.length(chapter.duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// The listener's chapter's bar and what's left of it, from the player's
/// clock while it plays: a view of its own, so only it redraws each second.
private struct ChapterHereProgress: View {
    @Environment(WatchPlayer.self) private var player
    let chapter: AudiobookChapter
    let isLoaded: Bool
    let keptPosition: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !(isLoaded && player.isPlaying))) { _ in
            let position = isLoaded ? player.livePosition : keptPosition
            let into = min(max(position - chapter.start, 0), chapter.duration)
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: chapter.duration > 0 ? into / chapter.duration : 0)
                    .tint(.accentColor)
                Text(WatchBookFormat.left(chapter.duration - into))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Moves the book loaded within the chapter playing with the Digital
/// Crown, as the iPhone's scrubber does: the time and bar follow the
/// crown, and the book goes there once it stops turning, playing or
/// paused. A book without chapters spans the whole book. Until the crown
/// turns, and once the book has got where it was sent, it follows the
/// player.
struct ChapterScrubScreen: View {
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchBookStore.self) private var books
    let key: String

    @State private var target: Double = 0
    @State private var chapter: AudiobookChapter?
    @State private var span: ClosedRange<Double> = 0...1
    /// Where the crown started from, while it turns.
    @State private var turnedFrom: Double?
    /// Until when a move just made holds the place shown, while the player
    /// gets there.
    @State private var holdUntil = Date.distantPast
    /// Where the place shown was taken from the player last.
    @State private var followed: Double = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let into = target - span.lowerBound
        let length = span.upperBound - span.lowerBound
        VStack(spacing: 6) {
            Text(chapter?.title ?? player.book?.title ?? "")
                .font(.footnote)
                .foregroundStyle(.tint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(WatchBookFormat.clock(into))
                .font(.system(.title2, design: .rounded))
                .monospacedDigit()
            ProgressView(value: length > 0 ? min(max(into / length, 0), 1) : 0)
                .tint(.accentColor)
            HStack {
                Text(change)
                Spacer(minLength: 4)
                Text("−\(WatchBookFormat.clock(span.upperBound - target))")
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            Text("Turn the Digital Crown")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .opacity(turnedFrom == nil ? 1 : 0)
        }
        .padding(.horizontal, 4)
        // The whole screen is the crown's: no ring round it.
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .digitalCrownRotation(
            $target,
            from: span.lowerBound,
            through: span.upperBound,
            by: step,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true,
            onChange: { _ in
                if turnedFrom == nil { turnedFrom = followed }
            },
            onIdle: { move() }
        )
        .task {
            follow()
            isFocused = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                follow()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(WatchBookFormat.clock(into)) of \(WatchBookFormat.clock(length))")
    }

    /// Whole seconds a step of the crown moves, so a chapter is about 120
    /// steps however long it runs: a second at a time in a short one, 15 in
    /// a long one.
    private var step: Double {
        min(max(((span.upperBound - span.lowerBound) / 120).rounded(), 1), 15)
    }

    /// "Back 1:05", "Ahead 0:30" while the crown has moved the place.
    private var change: String {
        guard let turnedFrom, abs(target - turnedFrom) >= 1 else { return "" }
        let by = WatchBookFormat.clock(abs(target - turnedFrom))
        return target < turnedFrom ? "Back \(by)" : "Ahead \(by)"
    }

    /// The place, its chapter and the crown's span, from the player: not
    /// while the crown turns or the book is on its way where it was sent.
    private func follow() {
        guard turnedFrom == nil, Date.now >= holdUntil, player.book?.key == key else { return }
        let position = player.livePosition
        let chapters = books.chapters(for: key)
        let here = chapters.count > 1 ? chapters.chapter(at: position) : nil
        // A second short of the end, which is the next chapter's start.
        let newSpan = here.map { $0.start...max($0.start, $0.end - 1) } ?? 0...max(player.bookDuration - 1, 0)
        if newSpan != span { span = newSpan }
        if here != chapter { chapter = here }
        followed = min(max(position, newSpan.lowerBound), newSpan.upperBound)
        target = followed
    }

    /// The crown has stopped: the book goes where it was turned to.
    private func move() {
        guard let from = turnedFrom else { return }
        turnedFrom = nil
        guard abs(target - from) >= 1 else { return }
        player.jump(to: target)
        holdUntil = .now.addingTimeInterval(1.5)
        WKInterfaceDevice.current().play(.click)
    }
}
