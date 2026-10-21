import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

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
