import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's place history (`AudiobookPlaceHistory`) as a timeline, newest
/// first and grouped by day: what happened where, in which chapter, how far
/// into the book (the ring round each marker), and how long ago, each on a
/// rail with a marker tinted by what it was. The rail breaks where the book
/// gave way to something else, a listening session's end, rather than
/// showing a row for it. A tap plays from there, and the place left for it
/// joins the list, so going back is never a loss.
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
                Text("Where you start, pause and jump in this book shows here, so you can always go back.")
            }
            .padding(.top, 24)
        } else {
            // Ticks once a minute, so "Just now" and "Today" move on while
            // it's open.
            TimelineView(.everyMinute) { context in
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Tap a moment to play from there. Where you were stays here, so you can always come back.")
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.6))
                        .padding(.top, 8)
                    ForEach(Self.days(places), id: \.day) { group in
                        Text(Self.dayTitle(group.day, now: context.date))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.6))
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        ForEach(Array(group.sessions.enumerated()), id: \.offset) { index, session in
                            // A gap in the rail where the book gave way to
                            // something else.
                            if index > 0 {
                                Spacer(minLength: 0)
                                    .frame(height: 14)
                            }
                            ForEach(session) { place in
                                Button {
                                    HapticManager.shared.fireHaptic(.selection)
                                    onPick()
                                    Task { await AudiobookPlayer.shared.pick(book, at: place.position, in: audiobook) }
                                } label: {
                                    row(
                                        place,
                                        now: context.date,
                                        isFirst: place.id == session.first?.id,
                                        isLast: place.id == session.last?.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row

    /// The marker on its rail, what happened and in which chapter, and on
    /// the trailing edge the place in the book over the time it happened.
    /// Opacities of primary, not `.secondary`, which flickers as the glass
    /// sheet changes.
    private func row(_ place: AudiobookPlaceHistory.Place, now: Date, isFirst: Bool, isLast: Bool) -> some View {
        let progress = self.progress(at: place.position)
        let detail = [
            audiobook?.chapter(at: place.position)?.title,
            progress.map { $0.formatted(.percent.precision(.fractionLength(0))) },
        ].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 14) {
            marker(place, progress: progress)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(place))
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.6))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(AudiobookFormat.clock(place.position))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
                Text(Self.time(place.date, now: now))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.6))
            }
            .monospacedDigit()
        }
        .padding(.vertical, 10)
        // The rail, behind the marker's column: from the row above to the
        // row below, with a gap where the marker sits (nothing opaque under
        // the marker, which on the glass sheet would show as a disc), and
        // broken at the day's first and last.
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Self.railColor)
                Color.clear
                    .frame(height: Self.ringSize + 4)
                Rectangle()
                    .fill(isLast ? Color.clear : Self.railColor)
            }
            .frame(width: 2)
            .padding(.leading, Self.ringSize / 2 - 1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays from here")
    }

    private static let markerSize: CGFloat = 26
    /// The marker and the progress ring round it.
    private static let ringSize: CGFloat = 32
    private static let railColor = Color.primary.opacity(0.2)

    /// How far into the book `position` is, 0 to 1; nil before the book
    /// is read whole.
    private func progress(at position: TimeInterval) -> Double? {
        guard let duration = audiobook?.duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    /// The kind's symbol on a disc of its tint, in a ring that fills with
    /// how far into the book it was. The tint kept soft, so the list reads
    /// as a timeline rather than a row of buttons.
    private func marker(_ place: AudiobookPlaceHistory.Place, progress: Double?) -> some View {
        let tint = Self.tint(place)
        return Image(systemName: Self.symbol(place))
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: Self.markerSize, height: Self.markerSize)
            .background(tint.opacity(0.2), in: .circle)
            .frame(width: Self.ringSize, height: Self.ringSize)
            .overlay {
                if let progress {
                    Circle()
                        .stroke(tint.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
    }

    // MARK: - Words and marks

    private static func title(_ place: AudiobookPlaceHistory.Place) -> LocalizedStringKey {
        switch place.kind {
        case .started: "Started listening"
        case .paused: "Paused"
        case .jumpedFrom: "Jumped from here"
        case .replaced:
            switch place.source {
            case .watch: "Before syncing with Apple Watch"
            case .plex: "Before syncing with Plex"
            case .audiobookshelf: "Before syncing with Audiobookshelf"
            case nil: "Before syncing"
            }
        // Not shown: a break in the rail (`days`).
        case .left: "Played something else"
        }
    }

    private static func symbol(_ place: AudiobookPlaceHistory.Place) -> String {
        switch place.kind {
        case .started: "play.fill"
        case .paused: "pause.fill"
        case .jumpedFrom: "arrow.turn.up.right"
        case .replaced:
            switch place.source {
            case .watch: "applewatch"
            case .plex, .audiobookshelf: "arrow.triangle.2.circlepath"
            case nil: "arrow.triangle.2.circlepath"
            }
        case .left: "arrow.right.square"
        }
    }

    private static func tint(_ place: AudiobookPlaceHistory.Place) -> Color {
        switch place.kind {
        case .started: .green
        case .paused: .orange
        case .jumpedFrom: .blue
        case .replaced: .purple
        case .left: .gray
        }
    }

    // MARK: - Days and times

    /// The places in runs of one day each, newest first, as they're kept,
    /// and each day in sessions: a place where the book gave way to
    /// something else (`.left`, which doesn't know whether to music or
    /// another book) isn't a row but the break between two.
    private static func days(_ places: [AudiobookPlaceHistory.Place]) -> [(day: Date, sessions: [[AudiobookPlaceHistory.Place]])] {
        let calendar = Calendar.current
        var days: [(day: Date, sessions: [[AudiobookPlaceHistory.Place]])] = []
        var breakBefore = false
        for place in places {
            let day = calendar.startOfDay(for: place.date)
            if place.kind == .left {
                breakBefore = true
                continue
            }
            if days.last?.day == day {
                if breakBefore, !(days[days.count - 1].sessions.last?.isEmpty ?? true) {
                    days[days.count - 1].sessions.append([place])
                } else {
                    days[days.count - 1].sessions[days[days.count - 1].sessions.count - 1].append(place)
                }
            } else {
                days.append((day, [[place]]))
            }
            breakBefore = false
        }
        return days
    }

    /// "Today", "Yesterday", a weekday this week, else "Oct 12".
    private static func dayTitle(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) {
            return String(localized: "Today")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            return day.formatted(.dateTime.month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// How long ago: "Just now", "12 min. ago", "8 hr. ago" within the
    /// last day; older, the time of day, the day being the heading above.
    private static func time(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return String(localized: "Just now")
        }
        if elapsed < 24 * 60 * 60 {
            return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
        return date.formatted(.dateTime.hour().minute())
    }
}
