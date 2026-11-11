import CloudStorage
import Defaults
import MusicKit
import MusicSearchKit
import OrderedCollections
import SonosKit
import SwiftUI

/// A cover with its title and artist under it, as the Music app draws its
/// library: the title with its explicit and favorite marks, the artist in
/// grey, and the menu on a long press (a right click on the Mac) rather than
/// a ••• over the cover. A tap opens an album or playlist and plays the
/// rest. Or, `artworkOnly`, just the cover, for a wall of artwork.
struct PlayableCardView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(FavoriteRatingCache.self) private var favoriteRatingCache
    @Environment(Router.self) private var router
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(\.zoomNamespace) private var zoomNamespace

    var item: PlayableContent
    var hideArtwork: Bool = false
    var hideAction: Bool = false
    /// Just the cover, square and edge to edge — no title, no corners — for
    /// a wall of artwork where the tiles touch. Tap and long-press keep
    /// working on the tile itself.
    var artworkOnly: Bool = false
    /// How wide the cover is on screen, in points. The cover is decoded no
    /// bigger than this needs, so a grid doesn't hold a 1200px bitmap for
    /// every tile.
    var artworkSize: Double = 200
    /// The artwork-only tile's corner rounding: none for a wall of tiles
    /// that touch, some for tiles set apart, as the Radio tab's are.
    var artworkCornerRadius: CGFloat = 0
    /// Whether the tile has a line under the title: a grid whose items have
    /// none leaves it off every tile (`TileGrid`'s playlists).
    var tileShowsSubtitle: Bool = true
    /// The menu as a context menu on a button, for a grid in a scroll view:
    /// built only when it's opened, where a `Menu` per tile builds every
    /// menu's content as the grid lays out. Off for tiles in a list row
    /// (`TileGrid`): a context menu there belongs to the whole row, so on the
    /// phone a long press lifted every tile and on the Mac every tile's right
    /// click opened the first one's menu; the card's `Menu`, held or right
    /// clicked, is theirs.
    var usesContextMenu: Bool = false
    /// Set by a grid whose tiles are zoom sources, so the album screen it
    /// opens grows out of the cover. The cover is marked here, the push
    /// told about it in `actions`.
    var zoomSource: ZoomTransitionSource? = nil

    /// The artist, else the subtitle (a playlist's curator, a station's
    /// kind).
    private var secondLine: String {
        item.metadata?.artist ?? item.subtitle
    }

    /// As the rows: Plex, Subsonic and the Apple Music library carry it.
    private var isFavorite: Bool {
        [.plex, .subsonic, .apple].contains(item.content.service)
            && (favoriteRatingCache.ratings[item.id] ?? item.metadata?.userRating ?? 0) > 0
    }

    var body: some View {
        VStack {
            if let add = adding?.add, add {
                content
            } else if artworkOnly || usesContextMenu {
                // A button with a context menu, not a `Menu` with a primary
                // action: a grid lays out dozens of tiles at once, and the
                // menu's content — nested menus, a download index refresh —
                // is not free per tile. A context menu is built only when
                // it is opened, and on a Mac it is the right-click anyway.
                Button {
                    actions()
                } label: {
                    // A little larger under the pointer, as a cover is in
                    // Music.
                    content
                        .largeWindowHoverLift()
                }
                .buttonStyle(.plain)
                .contentShape(.contextMenuPreview, .rect(cornerRadius: artworkOnly ? artworkCornerRadius : 8))
                .contextMenu {
                    PlayableMenuView(item: item)
                }
            } else {
                Menu {
                    PlayableMenuView(item: item)
                } label: {
                    content
                        .largeWindowHoverLift()
                } primaryAction: {
                    actions()
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .all)
    }

    @ViewBuilder
    private var content: some View {
        if artworkOnly {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ContentArtworkView(
                        content: item,
                        showMusicSource: false,
                        preferredSize: artworkSize,
                        cornerRadius: 0,
                        placeholderStyle: AnyShapeStyle(.quaternary)
                    )
                    .scaledToFill()
                }
                .clipShape(.rect(cornerRadius: artworkCornerRadius))
                .contentShape(.rect(cornerRadius: artworkCornerRadius))
                // Nothing written on the tile, so VoiceOver reads the name.
                .accessibilityLabel(item.title)
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .lineLimit(1)
                    if item.metadata?.isExplicit == true {
                        Image(systemName: "e.square.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Explicit")
                    }
                    if isFavorite {
                        Image(systemName: item.content.service == .apple ? "star.fill" : "heart.fill")
                            .font(.caption)
                            .foregroundStyle(item.content.service.brandColor)
                            .accessibilityLabel("Favorite")
                    }
                }
                if tileShowsSubtitle {
                    // Kept a line tall when empty, so a row of tiles lines up.
                    Text(secondLine)
                        .foregroundStyle(.secondary)
                        .lineLimit(1, reservesSpace: true)
                }
            }
            .font(.subheadline)
            // The default face even in the library page's rounded list, to
            // read as the Music app's grid does.
            .fontDesign(.default)
            // A menu's label takes the accent otherwise.
            .tint(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    /// The square cover, or a folder's collage, marked as the zoom source
    /// when the grid asked for one.
    @ViewBuilder
    private var cover: some View {
        let square = Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if item.content.type == .folder {
                    PlaylistFolderCollageView(folderID: item.content.id)
                } else {
                    ContentArtworkView(content: item, showMusicSource: false, preferredSize: artworkSize, cornerRadius: 0)
                        .scaledToFill()
                }
            }
            .clipShape(.rect(cornerRadius: 8))
        if let zoomSource, let zoomNamespace {
            square.zoomSource(zoomSource, in: zoomNamespace)
        } else {
            square
        }
    }

    private func actions() {
        if !hideAction {
            switch item.content.type {
            case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
                router.navigate(to: .mediaDetail(content: item, group: selectedGroupService.group, zoomSource: zoomSource))
            case .artist, .libraryArtist:
                router.navigate(to: .artistDetail(content: item, group: selectedGroupService.group))
            case .audiobook:
                router.navigate(to: .audiobookDetail(content: item))
            case .track, .favorite, .radio, .artistRadio, .songRadio, .liveRadio, .unique:
                play()
            case .folder:
                router.navigate(to: .folderBrowse(item: item, title: item.title))
            case .libraryTrack:
                break
            }
        } else {
            play()
        }
    }
    
    private func play(position: QueuePosition? = nil) {
        hideKeyboard()
        Task { @MainActor in
            let defaultPosition = position ?? QueuePosition.defaultPosition(
                for: item.content.type,
                // Read when played, not held in `@AppStorage`: any
                // UserDefaults write re-runs a view holding it, every card
                // on screen with it.
                replaceQueueByDefault: UserDefaults.standard.bool(forKey: Defaults.AppStorageKeys.defaultPlayAction)
            )
            let queueSong: ((GroupRoom, QueuePosition) async throws -> Void) = { group, selectedPosition in
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: selectedPosition))
                router.show(destination: .player(groupID: group.coordinatorID))
            }
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(item, position: defaultPosition, queue: queueSong)
                return
            }
            try await queueSong(group, defaultPosition)
        }
    }
}

#Preview {
    PlayableCardView(
        item: .init(
            title: "Radical Optimism",
            subtitle: "Dua Lipa",
            thumbnail: nil,
            artwork: URL(
                string: "https://i.scdn.co/image/ab67616d00001e02361debc2873b3aa493304b6d"
            ),
            content: .init(
                service: .spotify,
                id: "1Mo92916G2mmG7ajpmSVrc",
                type: .album,
                location: nil
            )
        )
    )
    .withEnvironments()
    .environment(SelectedGroupService(group: nil))
    .environment(Router())
}

#Preview {
    PlayableCardView(
        item: .init(
            title: "30",
            subtitle: "Adele",
            thumbnail: nil,
            artwork: URL(
                string: "https://i.scdn.co/image/ab67616d00001e02c6b577e4c4a6d326354a89f7"
            ),
            content: .init(
                service: .spotify,
                id: "1Mo92916G2mmG7ajpmSVrc",
                type: .album,
                location: nil
            )
        )
    )
    .withEnvironments()
    .environment(SelectedGroupService(group: nil))
    .environment(Router())
}
