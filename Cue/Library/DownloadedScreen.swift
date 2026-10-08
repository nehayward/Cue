import SonosKit
import SwiftUI

/// A provider's Downloaded page — the row under Songs on its library's
/// front page, the way the Music app has one: what's on this device from
/// that provider as a small library of its own, Play and Shuffle across
/// the lot, the albums that came down last, then Artists, Albums and
/// Songs. Everything here plays with no network, and on a speaker when
/// there is one.
///
/// Plex and Subsonic downloads are Cue's own, looked after in Settings ›
/// Downloads, which Manage in the toolbar opens as a sheet; Apple Music's
/// are the Music app's, which is where they're added and removed. With nil
/// for the provider it's the whole on-device library, the same one Offline
/// Mode shows.
struct DownloadedScreen: View {
    let service: MusicService?

    @Environment(Router.self) private var router: Router?
    @State private var downloads = DownloadManager.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared

    /// Whether Cue manages this provider's downloads. Nothing of Apple
    /// Music's is Cue's to manage.
    private var isManaged: Bool {
        service != .apple
    }

    var body: some View {
        // Read here so a download finishing or an index rebuilding
        // re-decides between the empty note and the library.
        let _ = downloads.completed.count
        let _ = apple.version
        let _ = files.indexVersion
        let isEmpty = OnDeviceLibrary.isEmpty(in: service)

        List {
            if isManaged {
                DownloadProgressSection(service: service, openManager: openManager)
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
        .navigationTitle("Downloaded")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isManaged {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Manage", action: openManager)
                }
            }
        }
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

    /// Settings › Downloads in a sheet: what's coming down, what's here
    /// and how big, the playback cache and the free limit. Settings
    /// rather than the manager alone, so it's the same place the Storage
    /// row reaches, with the rest of Settings a tap back.
    private func openManager() {
        HapticManager.shared.fireHaptic(.buttonPress)
        router?.presentedSheet = .settings(destination: .downloads)
    }
}

/// While songs are still coming down for a Downloaded page, how far along
/// they are, in one row: a tap opens the manager, where they're paused,
/// resumed or cancelled. Nothing while nothing is on its way.
private struct DownloadProgressSection: View {
    let service: MusicService?
    let openManager: @MainActor () -> Void

    @State private var downloads = DownloadManager.shared

    var body: some View {
        let pending = downloads.active.filter { service == nil || $0.service == service }
        if !pending.isEmpty {
            Section {
                Button(action: openManager) {
                    row(pending)
                }
            }
        }
    }

    private func row(_ pending: [DownloadManager.Item]) -> some View {
        let running = pending.filter(\.isActive)
        let fraction = pending.reduce(0.0) { $0 + $1.progress } / Double(pending.count)
        let waiting = !running.isEmpty && running.allSatisfy { downloads.waitsForNetwork($0) }

        let title: String
        let detail: String
        if running.isEmpty {
            title = pending.count == 1 ? "1 Download Stopped" : "\(pending.count) Downloads Stopped"
            detail = "Paused or failed"
        } else {
            title = running.count == 1 ? "Downloading 1 Song" : "Downloading \(running.count) Songs"
            detail = waiting
                ? (downloads.network == .none ? "Waiting for a connection" : "Waiting for Wi‑Fi")
                : "\(fraction.formatted(.percent.precision(.fractionLength(0)))) done"
        }

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: running.isEmpty ? "pause.fill" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)
            .animation(.linear(duration: 0.25), value: fraction)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

#Preview {
    NavigationStack {
        DownloadedScreen(service: .apple)
    }
    .withEnvironments()
}
