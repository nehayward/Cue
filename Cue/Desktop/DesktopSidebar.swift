import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Mac window's sidebar card (`DesktopShell`), after DaftMusic's: the
/// tabs, then the library of the service Browse shows (its collections, a
/// menu to switch service), then that library's playlists, and Settings at
/// the foot.
struct DesktopSidebar: View {
    @State private var appState = AppState.shared
    @State private var desktopRouter = Router.desktop
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    tabRows
                    DesktopLibrarySections()
                }
                .padding(12)
            }
            .scrollIndicators(.never)

            footer
        }
        .background(DesktopStyle.card)
        .clipShape(.rect(cornerRadius: DesktopStyle.cornerRadius))
    }

    @ViewBuilder
    private var tabRows: some View {
        if appState.showsBrowseTab {
            DesktopSidebarRow(tab: .browse, title: "Home") {
                Image("home.fill")
            }
        }
        if appState.showsRadioTab {
            DesktopSidebarRow(tab: .radio, title: "Radio") {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
        }
        if appState.showsAudiobooksTab {
            DesktopSidebarRow(tab: .audiobooks, title: "Audiobooks") {
                Image(systemName: "book.fill")
            }
        }
        if appState.showsDownloadsTab {
            DesktopSidebarRow(tab: .downloads, title: "Downloads", badge: appState.downloadsTabBadge) {
                appState.downloadsTabIcon
            }
        }
    }

    /// Settings, and Cue's name.
    private var footer: some View {
        HStack(spacing: 10) {
            Image("CueIconGlass")
                .resizable()
                .scaledToFit()
                .frame(width: 26 * DesktopStyle.scale(typeSize), height: 26 * DesktopStyle.scale(typeSize))
            Text("Cue")
                .font(.headline)
            Spacer(minLength: 0)
            Button {
                desktopRouter.presentedSheet = .settings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 36))
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Divider().padding(.horizontal, 16)
        }
    }
}

/// A tab's row: its glyph in a rounded tile, the accent's while it shows.
struct DesktopSidebarRow<Icon: View>: View {
    let tab: AppTab
    let title: String
    var badge: Int = 0
    @ViewBuilder var icon: () -> Icon

    @State private var desktop = DesktopState.shared

    var body: some View {
        let isSelected = desktop.isShowing(tab)

        Button {
            desktop.select(tab)
        } label: {
            DesktopSidebarLabel(title: title, isSelected: isSelected, badge: badge) {
                icon()
            }
        }
        .buttonStyle(.plain)
        .desktopHover(cornerRadius: 12, isSelected: false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row's look: a 36 pt tile with the glyph, and the title beside it.
struct DesktopSidebarLabel<Icon: View>: View {
    let title: String
    let isSelected: Bool
    var badge: Int = 0
    @ViewBuilder var icon: () -> Icon

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tile = (36 * DesktopStyle.scale(typeSize)).rounded()

        HStack(spacing: 12) {
            icon()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: tile, height: tile)
                .background(
                    isSelected ? AnyShapeStyle(Color("Accent")) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 10)
                )
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if badge > 0 {
                Text(badge, format: .number)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// A section's small capitals, with its button at the trailing end.
private struct DesktopSidebarHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Divider()
                .padding(.horizontal, 6)
                .padding(.top, 8)
        }
    }
}

/// The Library and Playlists sections, for the service Browse shows. The
/// stored choice is Browse's own, so switching here switches Browse too.
///
/// Only this reads it: any UserDefaults write runs a view holding
/// `@AppStorage` again, and what it hands `DesktopLibraryContent` is the
/// same service, so the rows under it aren't run again with it.
private struct DesktopLibrarySections: View {
    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple

    var body: some View {
        DesktopLibraryContent(browseService: browseMediaService)
    }
}

private struct DesktopLibraryContent: View {
    /// Its only input, so SwiftUI can tell it's unchanged (a closure here
    /// would read as new every time).
    let browseService: MediaSearchService

    /// Browse's choice, written as `@AppStorage` keeps it.
    private func choose(_ service: MediaSearchService) {
        guard service != browseService else { return }
        UserDefaults.standard.set(service.rawValue, forKey: AppStorageKeys.browseMediaService)
    }

    @State private var appState = AppState.shared

    /// Browse's service when it has collections to list, else the first
    /// switched on that does (Audiobookshelf, say, has its own tab).
    private var service: MediaSearchService? {
        let providers = appState.tabProviders
        return providers.contains(browseService) ? browseService : providers.first
    }

    /// The collections listed: the core ones, Recently Added where there's
    /// one, and not Playlists, which have their own section.
    private func collections(of service: MediaSearchService) -> [ProviderCollection] {
        var collections = service.defaultTabCollections.filter { $0 != .playlists }
        if service.tabCollections.contains(.recentlyAdded) {
            collections.append(.recentlyAdded)
        }
        return collections
    }

    var body: some View {
        if let service {
            DesktopSidebarHeader(title: "Library") {
                serviceMenu(current: service)
            }
            ForEach(collections(of: service), id: \.self) { collection in
                DesktopSidebarRow(tab: .providerCollection(service, collection), title: collection.title) {
                    Image(systemName: collection.systemImage)
                }
            }

            if service.tabCollections.contains(.playlists) {
                DesktopSidebarHeader(title: "Playlists") {
                    Button {
                        PlaylistMenuCommands.presentNewPlaylist()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.body)
                    }
                    .buttonStyle(DesktopIconButtonStyle(side: 28))
                    .help("New Playlist")
                    .accessibilityLabel("New Playlist")
                }
                DesktopPlaylistRows(service: service)
            }
        }
    }

    /// The service the library is of, switched from a menu when there's
    /// more than one.
    @ViewBuilder
    private func serviceMenu(current: MediaSearchService) -> some View {
        let providers = appState.tabProviders
        let label = HStack(spacing: 4) {
            current.tabImage
                .imageScale(.small)
            Text(current.title)
            if providers.count > 1 {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

        if providers.count > 1 {
            Menu {
                ForEach(providers, id: \.self) { provider in
                    Button {
                        choose(provider)
                    } label: {
                        Label {
                            Text(provider.title)
                        } icon: {
                            provider.tabImage
                        }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .tint(.secondary)
            .fixedSize()
            .help("Library")
        } else {
            label
        }
    }
}

/// The library's playlists, each opening its page in the content's place.
private struct DesktopPlaylistRows: View {
    let service: MediaSearchService

    @Environment(AppleMusicBrowseService.self) private var apple
    @Environment(PlexBrowseService.self) private var plex
    @Environment(SubsonicBrowseService.self) private var subsonic
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var desktop = DesktopState.shared

    /// Read from the browse services, which their screens fill too.
    private var playlists: [PlayableContent] {
        switch service {
        case .apple: Array(apple.userPlaylists)
        case .plex: Array(plex.userPlaylists)
        case .subsonic: Array(subsonic.userPlaylists)
        case .files: FilesLibraryService.shared.playlists
        default: []
        }
    }

    var body: some View {
        let cover = (36 * DesktopStyle.scale(typeSize)).rounded()

        ForEach(playlists) { playlist in
            let isSelected = desktop.isShowing(playlist)
            Button {
                desktop.open(playlist)
            } label: {
                HStack(spacing: 12) {
                    ContentArtworkView(content: playlist, showMusicSource: false)
                        .frame(width: cover, height: cover)
                        .clipShape(.rect(cornerRadius: 7))
                    Text(playlist.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .desktopHover(cornerRadius: 12, isSelected: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .task(id: service) {
            await load()
        }
    }

    /// The first page, if the services haven't one yet.
    private func load() async {
        switch service {
        case .apple:
            if apple.userPlaylists.isEmpty {
                await apple.updateUsersApplePlaylists(offset: 0)
            }
        case .plex:
            if plex.userPlaylists.isEmpty {
                await plex.updateUserPlaylists()
            }
        case .subsonic:
            if subsonic.userPlaylists.isEmpty {
                await subsonic.load()
            }
        case .files:
            await FilesLibraryService.shared.scanIfNeeded()
        default:
            break
        }
    }
}
