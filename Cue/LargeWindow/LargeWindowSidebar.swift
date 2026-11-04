import Defaults
import FocusOnAppear
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Mac and iPad window's sidebar (`LargeWindowShell`): the tabs, Search under
/// Home, then the library of the service Browse shows (its collections, a
/// menu to switch service), then that library's playlists, and Settings at
/// the foot.
struct LargeWindowSidebar: View {
    @State private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    tabRows
                    LargeWindowLibrarySections()
                }
                .padding(12)
            }
            .scrollIndicators(.never)

            footer
        }
        .catchesClicks()
        // The window's full height, as macOS 27's sidebars run: the rows
        // start below the title bar, the traffic lights in the corner above
        // them. No background: on the Mac it's clear over the window's
        // sidebar material (`MainWindowChrome`).
        .belowTitleBar()
    }

    @ViewBuilder
    private var tabRows: some View {
        if appState.showsBrowseTab {
            LargeWindowSidebarRow(tab: .browse, title: "Home") {
                Image("home.fill")
            }
        }
        LargeWindowSidebarRow(tab: .search, title: "Search") {
            Image(systemName: "magnifyingglass")
        }
        if appState.showsRadioTab {
            LargeWindowSidebarRow(tab: .radio, title: "Radio") {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
        }
        if appState.showsAudiobooksTab {
            LargeWindowSidebarRow(tab: .audiobooks, title: "Audiobooks") {
                Image(systemName: "book.fill")
            }
        }
        if appState.showsDownloadsTab {
            LargeWindowSidebarRow(tab: .downloads, title: "Downloads", badge: appState.downloadsTabBadge) {
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
                .frame(width: 26 * LargeWindowStyle.scale(typeSize), height: 26 * LargeWindowStyle.scale(typeSize))
            Text("Cue")
                .font(.headline)
            Spacer(minLength: 0)
            Button {
#if targetEnvironment(macCatalyst)
                SettingsWindow.shared.open()
#else
                // The stack on screen: nothing presents `Router.main`'s.
                LargeWindowState.shared.currentRouter.presentedSheet = .settings()
#endif
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(LargeWindowIconButtonStyle(side: 36))
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
struct LargeWindowSidebarRow<Icon: View>: View {
    let tab: AppTab
    let title: String
    var badge: Int = 0
    @ViewBuilder var icon: () -> Icon

    @State private var largeWindow = LargeWindowState.shared

    var body: some View {
        let isSelected = largeWindow.isShowing(tab)

        Button {
            largeWindow.select(tab)
        } label: {
            LargeWindowSidebarLabel(title: title, isSelected: isSelected, badge: badge) {
                icon()
            }
        }
        .buttonStyle(.plain)
        .largeWindowHover(cornerRadius: 12, isSelected: false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row's look: a 36 pt tile with the glyph, and the title beside it.
struct LargeWindowSidebarLabel<Icon: View>: View {
    let title: String
    let isSelected: Bool
    var badge: Int = 0
    @ViewBuilder var icon: () -> Icon

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tile = (36 * LargeWindowStyle.scale(typeSize)).rounded()

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
private struct LargeWindowSidebarHeader<Accessory: View>: View {
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
/// `@AppStorage` again, and what it hands `LargeWindowLibraryContent` is the
/// same service, so the rows under it aren't run again with it.
private struct LargeWindowLibrarySections: View {
    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple

    var body: some View {
        LargeWindowLibraryContent(browseService: browseMediaService)
    }
}

private struct LargeWindowLibraryContent: View {
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
            LargeWindowSidebarHeader(title: "Library") {
                serviceMenu(current: service)
            }
            ForEach(collections(of: service), id: \.self) { collection in
                LargeWindowSidebarRow(tab: .providerCollection(service, collection), title: collection.title) {
                    Image(systemName: collection.systemImage)
                }
            }

            if service.tabCollections.contains(.playlists) {
                LargeWindowSidebarHeader(title: "Playlists") {
                    NewPlaylistButton()
                }
                LargeWindowPlaylistRows(service: service)
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
/// The Playlists header's +: the new playlist named in a popover of Cue's
/// own, on the service the sidebar lists (`newPlaylistService`), rather
/// than UIKit's alert, which on the Mac drew Create as a rounded rectangle
/// beside a capsule Cancel. The menu bar's New Playlist keeps the alert, as
/// it opens over whatever is up.
private struct NewPlaylistButton: View {
    @State private var isNaming = false

    var body: some View {
        Button {
            isNaming = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.body)
        }
        .buttonStyle(LargeWindowIconButtonStyle(side: 28))
        .help("New Playlist")
        .accessibilityLabel("New Playlist")
        .popover(isPresented: $isNaming, arrowEdge: .trailing) {
            NewPlaylistPopover { isNaming = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// A name and Create, Cancel beside it the same size. Return creates,
/// Escape cancels.
private struct NewPlaylistPopover: View {
    let close: () -> Void

    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let service = PlaylistMenuCommands.newPlaylistService

        VStack(spacing: 16) {
            Text(service.map(NewPlaylistView.title(for:)) ?? "New Playlist")
                .font(.headline)

            TextField("Playlist Title", text: $name)
                .textFieldStyle(.plain)
                .focusOnAppear()
                .onSubmit { create(on: service) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.quaternary, in: .capsule)

            HStack(spacing: 10) {
                Button(role: .cancel, action: close) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button {
                    create(on: service)
                } label: {
                    Text("Create")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(service == nil || trimmedName.isEmpty)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 340)
    }

    private func create(on service: MusicService?) {
        let name = trimmedName
        guard let service, !name.isEmpty else { return }
        close()
        Task {
            await NewPlaylistView.create(named: name, on: service)
        }
    }
}

private struct LargeWindowPlaylistRows: View {
    let service: MediaSearchService

    @Environment(AppleMusicBrowseService.self) private var apple
    @Environment(PlexBrowseService.self) private var plex
    @Environment(SubsonicBrowseService.self) private var subsonic
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var largeWindow = LargeWindowState.shared

    /// For the rows' menus (`PlayableMenuView`), made once: one made in
    /// `body` would redraw every row reading it on each pass.
    private static let groupService = SelectedGroupService(group: nil)

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
        let cover = (36 * LargeWindowStyle.scale(typeSize)).rounded()

        // A stack, not the bare `ForEach`, for the load below: on a
        // `ForEach` of no playlists it never ran, so the list stayed empty
        // until a page that loads them (Home, Search) had been opened.
        VStack(alignment: .leading, spacing: 2) {
            rows(cover: cover)
        }
        .environment(largeWindow.currentRouter)
        .environment(Self.groupService)
        .task(id: service) {
            await load()
        }
    }

    private func rows(cover: CGFloat) -> some View {
        ForEach(playlists) { playlist in
            let isSelected = largeWindow.isShowing(playlist)
            Button {
                largeWindow.open(playlist)
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
            .largeWindowHover(cornerRadius: 12, isSelected: isSelected)
            // A playlist's own menu, as its row has elsewhere: play,
            // shuffle, play next, rename and delete. Its sheets go up from
            // the page on show.
            .contextMenu {
                PlayableMenuView(item: playlist)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
