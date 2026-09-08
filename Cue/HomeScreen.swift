import MusicSearchKit
import SonosKit
import SwiftUI

/// The first tab: where the library is set up and reached from. On iPhone
/// there is no sidebar to add a provider from, and a provider that isn't
/// set up yet — Files before a folder is chosen — has no tab to be found
/// in, so this is the one place that always shows every provider with a
/// way to add it, set it up, or open it.
///
/// With no network — or Offline Mode switched on — the providers give way
/// to what's on this device: the downloads and the Files folder's local
/// songs, with Play and Shuffle for the lot. See `OfflineMode`.
struct HomeScreen: View {
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(MusicSearchService.self) private var musicSearchService

    @State private var router = Router()
    @State private var tabProviders = TabProviderStore.shared
    @State private var files = FilesLibraryService.shared
    @State private var downloads = DownloadManager.shared
    @State private var offline = OfflineMode.shared

    /// Providers that can be tabs, in the order the app lists services.
    private var providers: [MediaSearchService] {
        MediaSearchService.allCases.filter(\.canBeTab)
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if offline.isActive {
                    offlineSection
                    onThisDeviceSection
                } else {
                    if !files.isConfigured {
                        filesSetupSection
                    }
                    tabsSection
                    providersSection
                }
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

    /// Why the providers aren't showing: the network is gone, or the user
    /// asked. The switch is the one thing worth offering here — with no
    /// network there's nothing to turn off.
    private var offlineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(offline.hasNetwork ? "Offline Mode" : "You're Offline")
                        .font(.headline)
                } icon: {
                    Image(systemName: offline.hasNetwork ? "airplane" : "wifi.slash")
                        .foregroundStyle(.secondary)
                }
                Text(offline.hasNetwork
                     ? "Showing only what's on this device. Everything plays here rather than on a speaker."
                     : "No connection, so this is what's on this device. It plays here; your speakers are back when the network is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if offline.isOn {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        withAnimation(.spring(response: 0.3)) {
                            offline.isOn = false
                        }
                    } label: {
                        Text("Turn Off Offline Mode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// What can play with nothing to reach: the downloads and the Files
    /// folder's local songs, each a row into its list, and Play and Shuffle
    /// across both. Empty, it says what to download next time.
    private var onThisDeviceSection: some View {
        let downloaded = downloads.completed
        let fileSongs = OnDeviceLibrary.fileSongs

        return Section {
            if downloaded.isEmpty, fileSongs.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on This Device", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download Plex or Subsonic songs from their menus, or keep a Files folder on this device, and they'll be here when you're offline.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                HStack(spacing: 12) {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Task { await playEverything(shuffle: false) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Task { await playEverything(shuffle: true) }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !downloaded.isEmpty {
                    NavigationLink(value: RouterDestination.playableList(
                        title: "Downloads",
                        showSectionIndex: false,
                        changeToken: { downloads.completed.count },
                        action: { offset in offset == 0 ? OnDeviceLibrary.downloadedSongs : [] }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Downloads")
                                Text(downloadsSubtitle(downloaded))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                    }
                }

                if !fileSongs.isEmpty {
                    NavigationLink(value: RouterDestination.playableList(
                        title: files.folderName ?? "Files",
                        showSectionIndex: false,
                        changeToken: { files.indexVersion },
                        action: { offset in offset == 0 ? OnDeviceLibrary.fileSongs : [] }
                    )) {
                        providerLabel(.files, subtitle: fileSongs.count == 1
                                      ? "1 song on this device"
                                      : "\(fileSongs.count.formatted()) songs on this device")
                    }
                }
            }
        } header: {
            Text("On This Device")
        }
    }

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

    private var tabsSection: some View {
        Section {
            if tabProviders.providers.isEmpty {
                Text("No providers in the tab view yet. Add one below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(tabProviders.providers) { provider in
                Button {
                    Router.main.selectedTab = .provider(provider.service)
                } label: {
                    HStack(spacing: 12) {
                        providerLabel(provider.service, subtitle: provider.collections.map(\.title).formatted(.list(type: .and, width: .narrow)))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
            Button {
                router.presentedSheet = .customizeTabs
            } label: {
                Label("Customize Tabs…", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Your Tabs")
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
            Text("Streaming services are signed in through the Sonos app and switched on in Settings › Services. Plex, Subsonic and Files are set up here in Cue.")
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
            // Only a choice while there's a network to leave; without one the
            // banner above already says why the providers are gone.
            if offline.hasNetwork {
                @Bindable var offline = offline
                Toggle(isOn: $offline.isOn.animation(.spring(response: 0.3))) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Offline Mode")
                            Text("Only what's on this device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "airplane")
                    }
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

    // MARK: - Offline playback

    /// Everything on the device into the local queue. Through the router
    /// rather than the player directly: it announces, records the play,
    /// and — offline — already sends everything to this device.
    private func playEverything(shuffle: Bool) async {
        // Shuffled here: the local queue's own shuffle only reorders the
        // pages of a container, and these are plain songs.
        let songs = shuffle ? OnDeviceLibrary.allSongs.shuffled() : OnDeviceLibrary.allSongs
        guard !songs.isEmpty else { return }
        await PlayDestinationRouter.play(songs, position: .replace) { group, position in
            try await SonosService.shared.queue(contents: songs, group: group, position: position, startIndex: 0)
        }
    }

    private func downloadsSubtitle(_ downloaded: [DownloadManager.Item]) -> String {
        let count = downloaded.count == 1 ? "1 song" : "\(downloaded.count.formatted()) songs"
        let services = Set(downloaded.map(\.service.title))
            .sorted()
            .formatted(.list(type: .and, width: .narrow))
        return services.isEmpty ? count : "\(count) • \(services)"
    }

    // MARK: - Rows

    /// One provider and the one thing to do with it next: open its tab,
    /// add it, set it up, or switch it on.
    @ViewBuilder
    private func providerRow(_ service: MediaSearchService) -> some View {
        let inTabs = tabProviders.contains(service)
        let isSelfHosted = service.isConfiguredInCue != nil
        let isSetUp = service.isConfiguredInCue ?? true
        let isEnabled = coreFeatures.isEnabled(service)

        HStack(spacing: 12) {
            providerLabel(service, subtitle: subtitle(for: service, inTabs: inTabs, isSelfHosted: isSelfHosted, isSetUp: isSetUp, isEnabled: isEnabled))
            Spacer(minLength: 0)
            if inTabs {
                Button {
                    Router.main.selectedTab = .provider(service)
                } label: {
                    Text("Open")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            } else if isSelfHosted, !isSetUp {
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
                    HapticManager.shared.fireHaptic(.buttonPress)
                    withAnimation(.spring(response: 0.3)) {
                        tabProviders.add(service)
                    }
                } label: {
                    Text("Add")
                }
                .buttonStyle(.borderedProminent)
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

    private func subtitle(for service: MediaSearchService, inTabs: Bool, isSelfHosted: Bool, isSetUp: Bool, isEnabled: Bool) -> String {
        if inTabs { return "In your tabs" }
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
