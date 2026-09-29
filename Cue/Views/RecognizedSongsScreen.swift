import NukeUI
import SonosKit
import SwiftUI

/// Every song the Shazam button has named, a day at a time. A song Apple
/// Music has is a full row — play, queue, add to a playlist — and one it
/// doesn't opens in Shazam.
///
/// Reached from the player's menu and from Settings → Music.
struct RecognizedSongsScreen: View {
    @State private var query = ""
    @State private var confirmClear = false

    private var history: RecognitionHistory { .shared }

    private var filtered: [RecognitionHistory.Entry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { entry in
            [entry.title, entry.artist, entry.station]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private struct Day: Identifiable {
        let day: Date
        var entries: [RecognitionHistory.Entry]
        var id: Date { day }
    }

    /// The entries by the day they were heard, newest day first.
    private var days: [Day] {
        let calendar = Calendar.current
        var days: [Day] = []
        for entry in filtered {
            let day = calendar.startOfDay(for: entry.date)
            if days.last?.day == day {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(Day(day: day, entries: [entry]))
            }
        }
        return days
    }

    var body: some View {
        List {
            ForEach(days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        row(entry)
                    }
                    .onDelete { offsets in
                        history.remove(Set(offsets.map { day.entries[$0].id }))
                    }
                } header: {
                    Text(Self.title(for: day.day))
                }
            }
        }
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Songs Yet", systemImage: "shazam.logo")
                } description: {
                    Text("Songs you identify with Shazam while a station plays show up here.")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Find in History")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                if !history.entries.isEmpty {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Remove All", systemImage: "trash.fill")
                            .labelStyle(.iconOnly)
                    }
                    .confirmationDialog("Clear Shazam History", isPresented: $confirmClear) {
                        Button("Remove All Songs", role: .destructive) {
                            history.removeAll()
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle("Shazam History")
    }

    @ViewBuilder
    private func row(_ entry: RecognitionHistory.Entry) -> some View {
        if let playable = entry.playable {
            PlayableContentView(item: playable, hideContentType: true)
        } else {
            UnmatchedSongRow(entry: entry)
        }
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(sameYear
            ? .dateTime.weekday(.wide).month(.wide).day()
            : .dateTime.month(.wide).day().year())
    }
}

/// A song Shazam named that Apple Music doesn't carry: its cover, where it
/// was heard, and a way out to Shazam.
private struct UnmatchedSongRow: View {
    @Environment(\.openURL) private var openURL

    let entry: RecognitionHistory.Entry

    var body: some View {
        Button {
            if let link = entry.link { openURL(link) }
        } label: {
            HStack(spacing: 12) {
                LazyImage(url: entry.artworkURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "shazam.logo.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if entry.link != nil {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(entry.link == nil)
    }

    private var subtitle: String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        return [entry.artist, entry.station, time]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
