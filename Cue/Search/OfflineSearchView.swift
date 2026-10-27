import SonosKit
import SwiftUI

/// The Search tab's rows while offline: the on-device library searched in
/// place of the services — artists and albums by name, songs by title,
/// artist or album — so the field keeps answering with no network at all.
/// With nothing typed, the songs downloaded last, to play. The field's
/// prompt says what it searches (`SearchScreen`), so there's no banner, and
/// no way into Artists or Albums: the Downloads tab beside it has those.
/// Sections for the `List` the search screen already owns.
struct OfflineSearchView: View {
    let query: String

    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    /// The last search's answer, and the query it was for.
    @State private var results: (artists: [OnDeviceLibrary.Group], albums: [OnDeviceLibrary.Group], songs: [PlayableContent]) = ([], [], [])
    @State private var searchedQuery = ""

    private struct SearchKey: Equatable {
        let query: String
        let changeToken: Int
    }

    /// How many of the songs downloaded last show with nothing typed.
    private static let recentCount = 25

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        Color.clear
            .frame(height: 0)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .onAppear {
                apple.refreshIfNeeded()
            }
            // Searched here rather than in the body: the body runs again on
            // every keystroke and every tick of a download's progress, and
            // each run rebuilt and sorted the whole on-device library. This
            // runs once the typing settles, and again when the songs here
            // change — a download finishing, an index rebuilding.
            .task(id: SearchKey(query: trimmed, changeToken: OnDeviceLibrary.changeToken)) {
                if !trimmed.isEmpty, !searchedQuery.isEmpty {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                }
                results = OnDeviceLibrary.search(trimmed)
                searchedQuery = trimmed
            }

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
                    ForEach(results.artists) { group in
                        NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
                            OnDeviceGroupRow(group: group, collection: .artists)
                        }
                    }
                } header: {
                    Text("Artists")
                }
            }
            if !results.albums.isEmpty {
                Section {
                    ForEach(results.albums) { group in
                        NavigationLink(value: OnDeviceLibrary.destination(for: group)) {
                            OnDeviceGroupRow(group: group, collection: .albums)
                        }
                    }
                } header: {
                    Text("Albums")
                }
            }
            if !results.songs.isEmpty {
                Section {
                    ForEach(results.songs) { song in
                        PlayableContentView(item: song, hideContentType: true)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Songs")
                        Spacer()
                        Text(results.songs.count == 1 ? "1 song" : "\(results.songs.count.formatted()) songs")
                            .textCase(nil)
                            .foregroundStyle(.secondary)
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
            ForEach(songs) { song in
                PlayableContentView(item: song, hideContentType: true)
            }
        } header: {
            Text("Recently Downloaded")
        }
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

#Preview {
    NavigationStack {
        List {
            OfflineSearchView(query: "a")
        }
        .listStyle(.plain)
    }
    .withEnvironments()
}
