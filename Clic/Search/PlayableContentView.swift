import CloudStorage
import MusicSearchKit
import Defaults
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct PlayableContentView: View {
    @Environment(Router.self) private var router: Router?
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    let item: PlayableContent
    var parent: PlayableContent?
    var hideArtwork: Bool = false
    var hideDetails: Bool = false
    var hideContentType: Bool = false
    var index: Int? = nil
    var dismissOnComplete: Bool = false
    var total: Int = 1

    var body: some View {
//        let _ = Self._printChanges()
//        let _ = print("\(item.title) update")
        VStack {
            if hideDetails || item.content.service == .unknown {
                content
            } else if let add = adding?.add, add, !item.content.type.isArtist {
                content
            } else {
                switch item.content.type {
                case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService?.group)) {
                        content
                    }
                    .listRowSeparator(.hidden, edges: .all)
                case .artist, .libraryArtist:
                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService?.group)) {
                        content
                    }
                case .folder:
                    NavigationLink(value: RouterDestination.folderBrowse(item: item, title: item.title)) {
                        folderContent
                    }
                case .track, .favorite, .radio, .songRadio, .artistRadio, .libraryTrack:
                    content
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: trailingInset))
    }

    private var content: some View {
        Button {
            play(position: item.content.type == .playlist ? .replace : .now)
        } label: {
            HStack {
                if let index {
                    Text(index, format: .number) // Display the number without leading zeros
                        .font(.caption.monospacedDigit())
                        .multilineTextAlignment(.center) // Center the text
                        .frame(width: 30, alignment: .center) // Ensure fixed width for 3 characters
                        .foregroundStyle(.secondary)
                }
                if !hideArtwork {
                    ContentArtworkView(content: item)
                        .frame(width: 50, height: 50)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text(item.title)
                            .lineLimit(1)
                            .foregroundStyle(selectedGroupService?.group?.coordinatorRoom.track.trackID == item.content.id.removingPercentEncoding  ? .accent : .primary)
                        Spacer()
                        if let isExplicit = item.metadata?.isExplicit, isExplicit {
                            Image(systemName: "e.square.fill")
                        }
                    }
                    HStack(spacing: 0) {
                        if !item.content.type.isRadio {
                            Text(
                                "\(!hideContentType ? item.content.type.title : "")\(!hideContentType && !item.subtitle.isEmpty ? " • " : "")\(item.subtitle)"
                            )
                            .truncationMode(.head)
                        } else {
                            Text(item.content.type.title)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                switch item.content.type {
                case .track, .favorite, .libraryTrack:
                    if adding == nil, !hideDetails {
                        Menu {
                            PlayableMenuView(item: item)
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(maxWidth: 50, maxHeight: .infinity)
                                .background(.clear)
                                .foregroundStyle(.primary)
                        }
                        .menuOrder(.priority)
                        .tint(.primary)
                    }
                default:
                    EmptyView()
                }
            }
            .fontDesign(.rounded)
        }
        .swipeActions {
            if [.playlist, .libraryPlaylist, .album, .track, .libraryTrack, .libraryAlbum].contains(item.content.type) {
                Button {
                    play(position: .next)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
            }
        }
        .contextMenu {
            if adding == nil, !hideDetails {
                PlayableMenuView(item: item)
            }
        }
        .draggable(item)
        .listRowSeparator(.hidden, edges: .all)
        .animation(.snappy, value: selectedGroupService?.group?.coordinatorRoom.track.trackID)
    }
    
    private var folderContent: some View {
        Label {
            Text(item.title)
            Text(item.content.type.title)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundStyle(.accent)
                .frame(width: 50, height: 50)
        }
        .lineLimit(1)
        .fontDesign(.rounded)
        .contextMenu {
            if adding == nil, !hideDetails {
                PlayableMenuView(item: item)
            }
        }
    }

    private func play(position: QueuePosition = .now) {
        if let add = adding?.add, add {
            adding?.content = item
            return
        }
        hideKeyboard()
        Task { @MainActor in
            let queueSong: ((GroupRoom) async throws -> Void) = { group in
                if let parent {
                    let position: QueuePosition = [.playlist, .libraryPlaylist].contains(parent.content.type) ? .replace : position
                    QueueManager.shared.addToQueue(item: QueueItem(playableContent: parent, group: group, position: position, index: index, total: total, showBanner: false))
                    Router.main.show(destination: .player(groupID: group.coordinatorID))
                    return
                }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: position, index: index, total: total, title: position.title))
            }
            
            guard let group = selectedGroupService?.group else {
                if let selectedGroupService {
                    router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong, content: item))
                }
                return
            }
            
            try await queueSong(group)
        }
    }

    private var trailingInset: Double {
        switch item.content.type {
        case .track, .favorite, .libraryTrack:
            return 0
        default:
            return 20
        }
    }
}
