import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's place history (`AudiobookPlaceHistory`) as a timeline, newest
/// first and grouped by day: what happened where, in which chapter, and how
/// long ago, each on a rail with a marker tinted by what it was. A play's
/// marker is ringed with how far into the book it was: the one place the
/// book's progress shows, since a ring or a bar on every row was busy. Each
/// day's heading carries how much of the book was listened to that day. The
/// rail breaks where the book gave way to something else, a listening
/// session's end, with what played instead in the gap rather than a row of
/// its own. A tap plays from there, and the place left for it joins the
/// list, so going back is never a loss. The words looked up in the book's
/// transcript (`BookWordLookups`) are rows among them, at the time they were
/// looked up: a tap shows the word's meaning again.
struct AudiobookHistoryList: View {
    let book: PlayableContent
    /// The book read whole, for its chapters' names; nil before it's read.
    let audiobook: Audiobook?
    /// After a place is picked: the sheet showing the list closes.
    var onPick: () -> Void = {}

    @State private var history = AudiobookPlaceHistory.shared
    @State private var lookups = BookWordLookups.shared

    var body: some View {
        let places = history.places(for: book)
        let words = lookups.lookups(for: book)
        if places.isEmpty, words.isEmpty {
            ContentUnavailableView {
                Label("No History Yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Every play, pause and skip in this book shows here, so you can always go back.")
            }
            .padding(.top, 24)
        } else {
            // Ticks once a minute, so "Just now" and "Today" move on while
            // it's open. Not lazy: a book keeps 50 places and 100 words at
            // most, and a lazy stack left a day's rows unbuilt under its
            // heading until the list was scrolled further.
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if words.isEmpty {
                            Text("Tap any moment to pick up from there.")
                        } else {
                            Text("Tap any moment to pick up from there, or a word to look it up again.")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.top, 8)
                    ForEach(Self.days(places, words), id: \.day) { group in
                        dayHeading(group, now: context.date)
                        ForEach(Array(group.sessions.enumerated()), id: \.offset) { index, session in
                            // The gap in the rail where the book gave way to
                            // something else, and what that was.
                            if let note = session.after, index > 0 || !note.isEmpty {
                                breakNote(note)
                                    .padding(.top, index > 0 ? 4 : 0)
                            }
                            VStack(spacing: 0) {
                                ForEach(session.entries) { entry in
                                    let isFirst = entry.id == session.entries.first?.id
                                    let isLast = entry.id == session.entries.last?.id
                                    switch entry {
                                    case .place(let place):
                                        Button {
                                            HapticManager.shared.fireHaptic(.selection)
                                            onPick()
                                            Task { await AudiobookPlayer.shared.pick(book, at: place.position, in: audiobook) }
                                        } label: {
                                            row(place, now: context.date, isFirst: isFirst, isLast: isLast)
                                        }
                                        .buttonStyle(.plain)
                                    case .word(let lookup):
                                        wordRow(lookup, now: context.date, isFirst: isFirst, isLast: isLast)
                                    }
                                }
                            }
                            .padding(.top, index > 0 && session.after == nil ? 14 : 0)
                        }
                    }
                }
            }
            // Words kept before their book was show in Words once it's known.
            .onAppear { lookups.keep(book) }
        }
    }

    // MARK: - Row

    /// The marker on its rail, what happened and in which chapter, and on
    /// the trailing edge the place in the book over how long ago. Opacities
    /// of primary, not `.secondary`, which flickers as the glass sheet
    /// changes.
    private func row(_ place: AudiobookPlaceHistory.Place, now: Date, isFirst: Bool, isLast: Bool) -> some View {
        let chapter = audiobook?.chapter(at: place.position)?.title
        return HStack(spacing: 14) {
            marker(place)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(place))
                    .foregroundStyle(.primary)
                if let chapter {
                    Text(chapter)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            when(place.position, place.date, now: now)
        }
        .padding(.vertical, 10)
        .background(alignment: .leading) { rail(isFirst: isFirst, isLast: isLast) }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays from here")
    }

    /// A word looked up: the word, marked as it was in its line, over the
    /// words around it. A tap shows its meaning again (`LookUpButton`);
    /// held, it offers to play from its line, to copy it, or to take it off
    /// the list.
    private func wordRow(_ lookup: BookWordLookups.Lookup, now: Date, isFirst: Bool, isLast: Bool) -> some View {
        LookUpButton(term: lookup.term) {
            HStack(spacing: 14) {
                marker(symbol: "character.book.closed", tint: Self.wordTint)
                BookWordLabel(lookup: lookup)
                Spacer(minLength: 8)
                when(lookup.position, lookup.date, now: now)
            }
            .padding(.vertical, 10)
            .background(alignment: .leading) { rail(isFirst: isFirst, isLast: isLast) }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookWordMenuItems(lookup: lookup, book: book, audiobook: audiobook, onPlay: onPick)
        }
    }

    /// The trailing edge of a row: the place in the book over how long ago.
    private func when(_ position: TimeInterval, _ date: Date, now: Date) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(AudiobookFormat.clock(position))
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.8))
            Text(Self.time(date, now: now))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.6))
        }
        .monospacedDigit()
    }

    /// The rail, behind the marker's column: from the row above to the row
    /// below, with a gap where the marker sits (nothing opaque under the
    /// marker, which on the glass sheet would show as a disc), and broken
    /// at a session's first and last.
    private func rail(isFirst: Bool, isLast: Bool) -> some View {
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

    private static let markerSize: CGFloat = 26
    /// The column every marker sits in, room for a play's ring.
    private static let ringSize: CGFloat = 32
    private static let railColor = Color.primary.opacity(0.2)
    private static let wordTint = Color.pink

    /// The kind's symbol on a disc of its tint, the tint kept soft so the
    /// list reads as a timeline rather than a row of buttons; a play's
    /// ringed with how far into the book it was.
    private func marker(_ place: AudiobookPlaceHistory.Place) -> some View {
        let progress: Double? = if place.kind == .started, let duration = audiobook?.duration, duration > 0 {
            min(max(place.position / duration, 0), 1)
        } else {
            nil
        }
        return marker(symbol: Self.symbol(place), tint: Self.tint(place), progress: progress)
    }

    private func marker(symbol: String, tint: Color, progress: Double? = nil) -> some View {
        Image(systemName: symbol)
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

    /// What happened, in a few words: "Resumed", "Paused", "Skipped ahead
    /// 10m 56s", "Synced from Apple Watch", "Marked as finished".
    private static func title(_ place: AudiobookPlaceHistory.Place) -> String {
        switch place.kind {
        case .started:
            return place.position < 1 ? String(localized: "Started") : String(localized: "Resumed")
        case .paused:
            return String(localized: "Paused")
        case .jumpedFrom:
            guard let to = place.to else { return String(localized: "Skipped") }
            let distance = abs(to - place.position)
            let amount = Duration.seconds(distance.rounded())
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
            return to >= place.position
                ? String(localized: "Skipped ahead \(amount)")
                : String(localized: "Went back \(amount)")
        case .replaced:
            switch place.source {
            case .watch: return String(localized: "Synced from Apple Watch")
            case .plex: return String(localized: "Synced from Plex")
            case .audiobookshelf: return String(localized: "Synced from Audiobookshelf")
            case nil: return String(localized: "Synced from another device")
            }
        case .marked:
            return place.to == 0 ? String(localized: "Marked as not started") : String(localized: "Marked as finished")
        // Not shown: a break in the rail (`days`).
        case .left:
            return String(localized: "Played something else")
        }
    }

    private static func symbol(_ place: AudiobookPlaceHistory.Place) -> String {
        switch place.kind {
        case .started: "play.fill"
        case .paused: "pause.fill"
        case .jumpedFrom:
            if let to = place.to, to < place.position { "arrow.uturn.backward" } else { "arrow.uturn.forward" }
        case .replaced:
            place.source == .watch ? "applewatch" : "arrow.triangle.2.circlepath"
        case .marked:
            place.to == 0 ? "arrow.counterclockwise" : "checkmark"
        case .left: "arrow.right.square"
        }
    }

    private static func tint(_ place: AudiobookPlaceHistory.Place) -> Color {
        switch place.kind {
        case .started: .green
        case .paused: .orange
        case .jumpedFrom: .blue
        case .replaced: .purple
        case .marked: .teal
        case .left: .gray
        }
    }

    // MARK: - Days and sessions

    /// A day's places, in listening sessions, and how much of the book was
    /// listened to over it.
    private struct Day {
        let day: Date
        var sessions: [Session]
        var listened: TimeInterval = 0
    }

    /// A run of places with the book playing, and the words looked up
    /// among them, and what took the player after it, when the run ended
    /// that way: its title, or "" for a break kept before the title was.
    private struct Session {
        var entries: [Entry]
        var after: String?
    }

    /// A row of the timeline.
    private enum Entry: Identifiable {
        case place(AudiobookPlaceHistory.Place)
        case word(BookWordLookups.Lookup)

        var id: UUID {
            switch self {
            case .place(let place): place.id
            case .word(let lookup): lookup.id
            }
        }

        var date: Date {
            switch self {
            case .place(let place): place.date
            case .word(let lookup): lookup.date
            }
        }
    }

    /// "Tuesday • 35m listened": the day, and the book time heard over it.
    private func dayHeading(_ group: Day, now: Date) -> some View {
        let listened = group.listened >= 60
            ? Duration.seconds(group.listened).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
            : nil
        return HStack(spacing: 6) {
            Text(Self.dayTitle(group.day, now: now))
                .fontWeight(.semibold)
            if let listened {
                Text("• \(listened) listened")
                    .monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(.primary.opacity(0.6))
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    /// The gap between two sessions, saying what played in it: a quiet
    /// line in the titles' column, not a row of its own. Empty for a break
    /// kept before what played was noted.
    private func breakNote(_ note: String) -> some View {
        HStack(spacing: 6) {
            if !note.isEmpty {
                Image(systemName: "music.note")
                Text(note)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.primary.opacity(0.5))
        .frame(height: 18)
        .padding(.leading, Self.ringSize + 14)
        .padding(.vertical, 2)
    }

    /// The places and words in runs of one day each, newest first, as
    /// they're kept; each day in sessions, a place where the book gave way
    /// to something else (`.left`) being not a row but the break between
    /// two; and each day's listening (`listened`), from the places alone.
    private static func days(_ places: [AudiobookPlaceHistory.Place], _ words: [BookWordLookups.Lookup]) -> [Day] {
        let calendar = Calendar.current
        let entries = (places.map(Entry.place) + words.map(Entry.word)).sorted { $0.date > $1.date }
        var days: [Day] = []
        var after: String?
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if case .place(let place) = entry, place.kind == .left {
                after = place.note ?? ""
                continue
            }
            if days.last?.day == day {
                if after != nil {
                    days[days.count - 1].sessions.append(Session(entries: [entry], after: after))
                } else {
                    days[days.count - 1].sessions[days[days.count - 1].sessions.count - 1].entries.append(entry)
                }
            } else {
                days.append(Day(day: day, sessions: [Session(entries: [entry], after: after)]))
            }
            after = nil
        }
        let listened = listened(places)
        for index in days.indices {
            days[index].listened = listened[days[index].day] ?? 0
        }
        return days
    }

    /// The book time heard each day, read off the places: between one and
    /// the next, oldest first, how far the book moved forward from where
    /// the first left it (a skip's destination, else its place), counted
    /// to the later one's day. A move faster than playing could go (4× the
    /// time between them) was a skip nobody noted, and doesn't count.
    private static func listened(_ places: [AudiobookPlaceHistory.Place]) -> [Date: TimeInterval] {
        let calendar = Calendar.current
        var days: [Date: TimeInterval] = [:]
        let oldestFirst = Array(places.reversed())
        for (earlier, later) in zip(oldestFirst, oldestFirst.dropFirst()) {
            let from = earlier.to ?? earlier.position
            let moved = later.position - from
            let elapsed = later.date.timeIntervalSince(earlier.date)
            guard moved > 0, moved <= elapsed * 4 + 5 else { continue }
            days[calendar.startOfDay(for: later.date), default: 0] += moved
        }
        return days
    }

    // MARK: - Days and times

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

    /// How long ago: "Just now", "12 min. ago", "8 hr. ago", "3 days ago".
    private static func time(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "Just now")
        }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
