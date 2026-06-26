import CloudStorage
import MusicSearchKit
import Defaults
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct PlayableArtworkView: View {
    @Environment(Router.self) private var router: Router?
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    
    let item: PlayableContent
    var parent: PlayableContent?
    var hideArtwork: Bool = false
    var hideDetails: Bool = false
    var hideContentType: Bool = false
    var index: Int? = nil
    var dismissOnComplete: Bool = false
    var total: Int = 1
    
    var body: some View {
        content
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: trailingInset))
            .draggable(item)
            .listRowSeparator(.hidden, edges: .all)
            .animation(.snappy, value: selectedGroupService?.group?.coordinatorRoom.track.trackID)
    }
    
    private var content: some View {
        Menu {
            PlayableMenuView(item: item)
        } label: {
            ContentArtworkView(content: item, preferredSize: 100)
        } primaryAction: {
            primaryAction()
        }
    }
    
    private func primaryAction() {
        if let add = adding?.add, add {
            adding?.content = item
            return
        }
        switch item.content.type {
        case .folder:
            router?.navigate(to: .folderBrowse(item: item, title: item.title))
        case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
            router?.navigate(to: .mediaDetail(content: item, group: selectedGroupService?.group))
        case .artist, .libraryArtist:
            router?.navigate(to: .artistDetail(content: item, group: selectedGroupService?.group))
        case .track, .favorite, .radio, .artistRadio, .liveRadio, .songRadio, .unique:
            play()
        case .libraryTrack:
            break
        }
    }
    
    private func play(position: QueuePosition? = nil) {
        if let add = adding?.add, add {
            adding?.content = item
            return
        }
        hideKeyboard()
        Task { @MainActor in
            let defaultPosition = position ?? QueuePosition.defaultPosition(
                for: (parent ?? item).content.type,
                replaceQueueByDefault: replaceQueueByDefault
            )
            let queueSong: ((GroupRoom, QueuePosition) async throws -> Void) = { [item, parent, index, total] group, selectedPosition in
                if let parent {
                    QueueManager.shared.addToQueue(item: QueueItem(playableContent: parent, group: group, position: selectedPosition, index: index, total: total, showBanner: false))
                    Router.main.show(destination: .player(groupID: group.coordinatorID))
                    return
                }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: selectedPosition, index: index, total: total, title: selectedPosition.title))
            }

            guard let group = selectedGroupService?.group else {
                if let selectedGroupService {
                    router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onQueueSelection: queueSong, defaultPosition: defaultPosition, content: item))
                }
                return
            }

            try await queueSong(group, defaultPosition)
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
