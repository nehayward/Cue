import SonosKit
import SwiftUI

/// The Search tab's rows while offline: the on-device library searched in
/// place of the services — artists and albums by name, songs by title,
/// artist or album — so the field keeps answering with no network at all.
/// With nothing typed, the songs downloaded last, to play. The field's
/// prompt says what it searches (`SearchScreen`), so there's no banner, and
/// no way into Artists or Albums: the Downloads tab beside it has those.
/// Sections for the `List` the search screen already owns, which runs the
/// search (`OfflineSearch`) from its own `.task`: run from a row of these,
/// it took an empty row, and the gap it left, at the top.
struct OfflineSearchView: View {
    let query: String
    let search: OfflineSearch

    @State private var downloads = DownloadManager.shared

    /// How many of the songs downloaded last show with nothing typed.
    private static let recentCount = 25

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = search.results
        let searchedQuery = search.searchedQuery

        if trimmed.isEmpty {
            if OnDeviceLibrary.isEmpty {
                emptyLibrary
            } else {
                recentSection
            }
        } else if searchedQuery == trimmed, results.artists.isEmpty, results.albums.isEmpty, results.songs.isEmpty {
            ContentUnavailableView.search(text: trimmed)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            if !results.artists.isEmpty {
                Section {
                    titleRow("Artists")
                    ForEach(results.artists) { group in
                        groupRow(group, collection: .artists)
                    }
                }
            }
            if !results.albums.isEmpty {
                Section {
                    titleRow("Albums")
                    ForEach(results.albums) { group in
                        groupRow(group, collection: .albums)
                    }
                }
            }
            if !results.songs.isEmpty {
                Section {
                    titleRow("Songs", count: results.songs.count == 1 ? "1 song" : "\(results.songs.count.formatted()) songs")
                    ForEach(results.songs) { song in
                        PlayableContentView(item: song, hideContentType: true)
                    }
                }
            }
        }
    }

    /// With nothing typed, the songs downloaded last, a tap playing one:
    /// the tab is a way in before it's a field.
    private var recentSection: some View {
        let _ = downloads.musicSummary
        let songs = Array(OnDeviceLibrary.songs(sortedBy: .added, descending: true).prefix(Self.recentCount))
        return Section {
            titleRow("Recently Downloaded")
            ForEach(songs) { song in
                PlayableContentView(item: song, hideContentType: true)
            }
        }
    }

    /// A section's title as its first row, not its header, which a plain
    /// list pads well clear of what's above; a count on the right.
    private func titleRow(_ title: LocalizedStringKey, count: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
            Spacer(minLength: 8)
            if let count {
                Text(count)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
    }

    /// An artist or album, drawn as the Albums and Artists pages draw
    /// theirs: tight, no separators.
    private func groupRow(_ group: OnDeviceLibrary.Group, collection: OnDeviceCollection) -> some View {
        NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
            OnDeviceGroupRow(group: group, collection: collection)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Nothing on This Device", systemImage: "arrow.down.circle")
        } description: {
            Text("Download Plex or Subsonic songs from their menus, download Apple Music songs in the Music app, or keep a Files folder on this device, and you can search them here when you're offline.")
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// The offline search's answer and the query it was for. Searched off
/// the body: the body runs on every keystroke, and each run rebuilt and
/// sorted the whole on-device library. `SearchScreen` runs it once the
/// typing settles, and again when the songs here change — a download
/// finishing, an index rebuilding (`Key`).
@MainActor
@Observable
final class OfflineSearch {
    struct Key: Equatable {
        let query: String
        let changeToken: Int
    }

    private(set) var results: (artists: [OnDeviceLibrary.Group], albums: [OnDeviceLibrary.Group], songs: [PlayableContent]) = ([], [], [])
    private(set) var searchedQuery = ""

    func run(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !searchedQuery.isEmpty {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        AppleDownloadsIndex.shared.refreshIfNeeded()
        results = OnDeviceLibrary.search(trimmed)
        searchedQuery = trimmed
    }
}

#Preview {
    NavigationStack {
        List {
            OfflineSearchView(query: "a", search: OfflineSearch())
        }
        .listStyle(.plain)
    }
    .withEnvironments()
}
