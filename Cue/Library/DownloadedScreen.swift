import SonosKit
import SwiftUI

/// A provider's Downloaded page — the row under Songs on its library's
/// front page, the way the Music app has one: what's on this device from
/// that provider as a small library of its own, Artists, Albums and Songs,
/// with Play and Shuffle across the lot. Everything here plays with no
/// network, and on a speaker when there is one.
///
/// Plex and Subsonic downloads are Cue's own, managed under Downloads;
/// Apple Music's are the Music app's, which is where they're added and
/// removed. With nil for the provider it's the whole on-device library,
/// the same one Offline Mode shows.
struct DownloadedScreen: View {
    let service: MusicService?

    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        // Read here so a download finishing or an index rebuilding
        // re-decides between the empty note and the library.
        let _ = downloads.completed.count
        let _ = apple.version
        let _ = files.indexVersion
        let isEmpty = OnDeviceLibrary.isEmpty(in: service)

        List {
            if isEmpty {
                emptySection
            } else {
                OnDeviceLibrarySections(service: service)
            }
            if service != .apple {
                manageSection
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .contentMargins(.horizontal, 16)
        .miniPlayerOnScrollHandler()
        .navigationTitle("Downloaded")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apple.refreshIfNeeded()
        }
    }

    /// Empty, it says how this provider's songs get here.
    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("Nothing Downloaded", systemImage: "arrow.down.circle")
            } description: {
                Text(OnDeviceLibrary.emptyDescription(for: service))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Where Cue's own downloads are looked after — what's coming down,
    /// what's here and how big, and the free limit. Not for Apple Music:
    /// nothing of its downloads is Cue's to manage.
    private var manageSection: some View {
        Section {
            NavigationLink(value: RouterDestination.downloads) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Downloads")
                        Text(downloads.hasActiveDownloads
                             ? (downloads.active.count == 1 ? "1 downloading" : "\(downloads.active.count) downloading")
                             : "Storage, cellular and the playback cache")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DownloadedScreen(service: .apple)
    }
    .withEnvironments()
}
