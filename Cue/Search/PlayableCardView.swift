import CloudStorage
import Defaults
import MusicKit
import MusicSearchKit
import OrderedCollections
import SonosKit
import SwiftUI

struct PlayableCardView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    
    var item: PlayableContent
    var hideArtwork: Bool = false
    var hideAction: Bool = false
    /// Just the cover, square and edge to edge — no title, no corners, no
    /// menu button — for a wall of artwork where the tiles touch. Tap and
    /// long-press keep working on the tile itself.
    var artworkOnly: Bool = false

    var body: some View {
        VStack {
            if let add = adding?.add, add {
                content
            } else {
                Menu {
                    PlayableMenuView(item: item)
                } label: {
                    content
                } primaryAction: {
                    actions()
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .all)
        .overlay(alignment: .topTrailing) {
            if adding == nil && !hideAction && !artworkOnly {
                Menu {
                    PlayableMenuView(item: item)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("More Options for \(item.title)")
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                        .shadow(radius: 4)
                        .frame(maxWidth: 44, maxHeight: 44)
                }
                .frame(maxWidth: 44, maxHeight: 44)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if artworkOnly {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ContentArtworkView(content: item, showMusicSource: false, preferredSize: 500)
                        .scaledToFill()
                }
                .clipped()
                .contentShape(.rect)
        } else {
            card
        }
    }

    private var card: some View {
        VStack {
            if item.content.type == .folder {
                PlaylistFolderCollageView(folderID: item.content.id)
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.55), .clear, .clear], startPoint: .bottom, endPoint: .top)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .bold()
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .opacity(0.8)
                            }
                        }
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .fontDesign(.rounded)
                        .padding([.horizontal, .bottom], 12)
                        .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 20)
            } else {
                ContentArtworkView(content: item, showMusicSource: false, preferredSize: 500)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading) {
                    Text(item.title)
                        .fontWeight(.semibold)
                    Text(item.subtitle)
                        .opacity(0.8)
                }
                .lineLimit(1, reservesSpace: true)
                .fontDesign(.rounded)
                .tint(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func actions() {
        if !hideAction {
            switch item.content.type {
            case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
                router.navigate(to: .mediaDetail(content: item, group: selectedGroupService.group))
            case .artist, .libraryArtist:
                router.navigate(to: .artistDetail(content: item, group: selectedGroupService.group))
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
                replaceQueueByDefault: replaceQueueByDefault
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
