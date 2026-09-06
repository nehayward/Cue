import MusicSearchKit
import SonosKit
import SwiftUI

/// The first tab on iPad and Mac: where the library is set up and reached
/// from. A provider that isn't set up yet — Files before a folder is
/// chosen — has no section in the sidebar to be found in, so this is the
/// one place that always shows every provider with a way to set it up,
/// switch it on, or open it. The phone has no Home tab; Browse takes its
/// place there, and providers are set up in Settings › Services.
struct HomeScreen: View {
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(MusicSearchService.self) private var musicSearchService

    @State private var router = Router()
    @State private var files = FilesLibraryService.shared
    @State private var downloads = DownloadManager.shared

    /// Providers that can be tabs, in the order the app lists services.
    private var providers: [MediaSearchService] {
        MediaSearchService.allCases.filter(\.canBeTab)
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if !files.isConfigured {
                    filesSetupSection
                }
                providersSection
                moreSection
            }
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .contentMargins(.horizontal, 16)
            .fontDesign(.rounded)
            .navigationTitle("Home")
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    // MARK: - Sections

    /// Files before a folder is chosen: the one setup that starts from
    /// nothing, so it gets the top of the screen until it's done.
    private var filesSetupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Play music from a folder")
                        .font(.headline)
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(MusicService.files.brandColor)
                }
                Text("Pick a folder on this device or in iCloud Drive. Cue reads the tags, keeps playlists as .m3u files, and plays everything on this device — no account needed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    router.presentedSheet = .filesManagement
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private var providersSection: some View {
        Section {
            ForEach(providers, id: \.self) { service in
                providerRow(service)
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("Streaming services are signed in through the Sonos app and switched on in Settings › Services. Plex, Subsonic and Files are set up here in Cue. Every provider that's on has a section in the sidebar; use the sidebar's Edit to hide or reorder its tabs.")
        }
    }

    private var moreSection: some View {
        Section {
            NavigationLink(value: RouterDestination.downloads) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloads")
                        Text(downloads.hasActiveDownloads
                             ? (downloads.active.count == 1 ? "1 downloading" : "\(downloads.active.count) downloading")
                             : (downloads.completed.isEmpty ? "Nothing kept yet" : "\(downloads.completed.count) songs on this device"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
            }
            Button {
                router.presentedSheet = .settings()
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .tint(.primary)
        }
    }

    // MARK: - Rows

    /// One provider and the one thing to do with it next: set it up,
    /// switch it on, or open its section. A provider that is on has a
    /// section — there is no adding any more.
    @ViewBuilder
    private func providerRow(_ service: MediaSearchService) -> some View {
        let isSelfHosted = service.isConfiguredInCue != nil
        let isSetUp = service.isConfiguredInCue ?? true
        let isEnabled = coreFeatures.isEnabled(service)

        HStack(spacing: 12) {
            providerLabel(service, subtitle: subtitle(for: service, isSelfHosted: isSelfHosted, isSetUp: isSetUp, isEnabled: isEnabled))
            Spacer(minLength: 0)
            if isSelfHosted, !isSetUp {
                Button {
                    if let sheet = service.managementSheet {
                        router.presentedSheet = sheet
                    }
                } label: {
                    Text("Set Up")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else if isEnabled {
                Button {
                    Router.main.selectedTab = .provider(service)
                } label: {
                    Text("Open")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            } else {
                Button {
                    router.presentedSheet = .settings(destination: .servicePreferenceScreen)
                } label: {
                    Text("Turn On")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private func subtitle(for service: MediaSearchService, isSelfHosted: Bool, isSetUp: Bool, isEnabled: Bool) -> String {
        if isSelfHosted, !isSetUp {
            return service == .files ? "Choose a folder of music" : "Connect your server"
        }
        if !isEnabled { return "Off in Settings › Services" }
        if service == .files, let name = files.folderName { return name }
        return service.tabCollections.map(\.title).formatted(.list(type: .and, width: .narrow))
    }

    private func providerLabel(_ service: MediaSearchService, subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            service.iconForMusicService
                .frame(width: 24, height: 24)
        }
    }
}

#Preview {
    HomeScreen()
        .withEnvironments()
}
