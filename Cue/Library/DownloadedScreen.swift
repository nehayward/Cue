import SonosKit
import SwiftUI

/// What's on this device as a small library of its own, Artists, Albums
/// and Songs, with Play and Shuffle across the lot. Everything here plays
/// with no network, and on a speaker when there is one.
///
/// With nil for the provider it's the Downloads tab (`DownloadsTabScreen`):
/// the whole on-device library, the same one Offline Mode shows, led by
/// what's still coming down, with Storage in the toolbar. With a provider it's
/// that provider's songs here (Apple Music's, from Settings ▸ Storage).
///
/// Plex and Subsonic downloads are Cue's own, managed under Storage;
/// Apple Music's are the Music app's, which is where they're added and
/// removed.
struct DownloadedScreen: View {
    let service: MusicService?

    @Environment(Router.self) private var router
    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    var body: some View {
        // Read here so a download finishing or an index rebuilding
        // re-decides between the empty note and the library. The summary,
        // not the downloads themselves, which move with every byte.
        let _ = downloads.musicSummary
        let _ = apple.version
        let _ = files.indexVersion
        // The tab lists the books downloaded too.
        let isEmpty = OnDeviceLibrary.isEmpty(in: service) && (service != nil || downloads.musicSummary.books == 0)

        List {
            // While songs or books come down, how far they've got leads.
            if managesDownloads, downloads.musicSummary.remainingDownloads > 0 {
                downloadingSection
            }
            if isEmpty {
                emptySection
            } else {
                OnDeviceLibrarySections(service: service)
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .contentMargins(.horizontal, 16)
        .miniPlayerOnScrollHandler()
        .navigationTitle(service == nil ? "Downloads" : "Downloaded")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if managesDownloads {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        router.navigate(to: .downloads)
                    } label: {
                        // A gear, as it's the downloads' settings: storage,
                        // cellular and the cache.
                        Label("Storage", systemImage: "gearshape")
                    }
                }
            }
        }
        .onAppear {
            apple.refreshIfNeeded()
        }
    }

    /// Whether this page leads to where Cue's own downloads are looked
    /// after — what's coming down, what's here and how big, and the free
    /// limit. Not Apple Music's, opened from there: nothing of its
    /// downloads is Cue's to manage.
    private var managesDownloads: Bool {
        service != .apple
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

    /// How far the songs and books coming down have got, opening Storage
    /// on them. Only while they come down: Storage is otherwise the
    /// toolbar's.
    private var downloadingSection: some View {
        Section {
            NavigationLink(value: RouterDestination.downloads) {
                Label {
                    DownloadingProgress(summary: downloads.musicSummary)
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// How far the songs and books coming down have got: the run's songs and
/// the books, and a bar that moves with the bytes. Its own view, the one
/// that reads every byte of progress, so only this row redraws as they
/// arrive.
private struct DownloadingProgress: View {
    let summary: DownloadManager.MusicSummary

    @State private var downloads = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Downloading")
            ProgressView(value: downloads.runFraction(for: summary))
                .progressViewStyle(.linear)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// "9 of 12 songs", and the books, each counting once.
    private var detail: String {
        var parts: [String] = []
        if summary.runTotal > 0 {
            parts.append("\(summary.runSettled) of \(summary.runTotal == 1 ? "1 song" : "\(summary.runTotal) songs")")
        }
        if summary.booksRemaining > 0 {
            parts.append(summary.booksRemaining == 1 ? "1 book" : "\(summary.booksRemaining) books")
        }
        return parts.joined(separator: " • ")
    }
}

/// The Downloads tab, shown while there's music downloaded or coming down
/// (`CueApp.showsDownloadsTab`): every provider's songs on this device,
/// with what's still to come on top.
struct DownloadsTabScreen: View {
    /// This tab's own stack, never a shared router: two stacks bound to one
    /// path push each other.
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            DownloadedScreen(service: nil)
                .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }
}

#Preview {
    NavigationStack {
        DownloadedScreen(service: .apple)
    }
    .environment(Router())
    .withEnvironments()
}
