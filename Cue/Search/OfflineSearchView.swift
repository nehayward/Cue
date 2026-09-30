import SonosKit
import SwiftUI

/// The Search tab's rows while `OfflineMode` is active: the on-device
/// library searched in place of the services — artists and albums by name,
/// songs by title, artist or album — so the field keeps answering with no
/// network at all. Sections for the `List` the search screen already owns.
struct OfflineSearchView: View {
    let query: String

    @State private var offline = OfflineMode.shared
    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        // Read here so a download finishing or an index rebuilding re-runs
        // the search; the library itself is static.
        let _ = downloads.completed.count
        let _ = apple.version
        let _ = files.indexVersion
        let results = OnDeviceLibrary.search(query)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        statusRow

        if trimmed.isEmpty {
            if OnDeviceLibrary.isEmpty {
                emptyLibrary
            } else {
                librarySection
            }
        } else if results.artists.isEmpty, results.albums.isEmpty, results.songs.isEmpty {
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

    /// One line on what's being searched, and why it isn't the services.
    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: offline.hasNetwork ? "airplane" : "wifi.slash")
                .foregroundStyle(.secondary)
            Text(offline.hasNetwork
                 ? "Offline Mode — searching what's on this device"
                 : "No connection — searching what's on this device")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .onAppear {
            apple.refreshIfNeeded()
        }
    }

    /// With nothing typed yet, the library's grouped pages, so the tab is
    /// still a way in rather than a blank field; typing searches the songs.
    private var librarySection: some View {
        Section {
            NavigationLink(value: RouterDestination.onDeviceCollection(.artists)) {
                Label("Artists", systemImage: OnDeviceCollection.artists.systemImage)
            }
            NavigationLink(value: RouterDestination.onDeviceCollection(.albums)) {
                Label("Albums", systemImage: OnDeviceCollection.albums.systemImage)
            }
        } header: {
            Text("On This Device")
        } footer: {
            Text("Type to search the songs, albums and artists on this device.")
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
