import CloudStorage
import Defaults
import MusicKit
import MusicSearchKit
import OrderedCollections
import SonosKit
import SwiftUI

struct PlayableContentView: View {
    private static let swipeableTypes: Set<ContentType> = [.playlist, .libraryPlaylist, .album, .track, .libraryTrack, .libraryAlbum]
    
    @Environment(Router.self) private var router: Router?
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?
    @Environment(PlexRatingCache.self) private var plexRatingCache
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    
    let item: PlayableContent
    var parent: PlayableContent?
    var hideArtwork: Bool = false
    var hideDetails: Bool = false
    var hideContentType: Bool = false
    var index: Int? = nil
    var dismissOnComplete: Bool = false
    var total: Int = 1
    
    private var isCurrentlyPlaying: Bool {
        guard let trackID = selectedGroupService?.group?.coordinatorRoom.track.trackID else { return false }
        return trackID == item.content.id.removingPercentEncoding
    }
    
    private var subtitleText: String {
        if item.content.type.isRadio {
            return item.content.type.title
        }
        if hideContentType {
            return item.subtitle
        }
        if item.subtitle.isEmpty {
            return item.content.type.title
        }
        return "\(item.content.type.title) • \(item.subtitle)"
    }
    
    private var shouldShowPlainContent: Bool {
        hideDetails || item.content.service == .unknown || (adding?.add == true && !item.content.type.isArtist)
    }
    
    var body: some View {
//        let _ = Self._printChanges()
//        let _ = print("\(item.title) update")
        VStack {
            if shouldShowPlainContent {
                content
            } else {
                switch item.content.type {
                case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService?.group)) {
                        content
                    }
                case .artist, .libraryArtist:
                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService?.group)) {
                        content
                    }
                case .folder:
                    NavigationLink(value: RouterDestination.folderBrowse(item: item, title: item.title)) {
                        folderContent
                    }
                case .track, .favorite, .radio, .songRadio, .artistRadio, .libraryTrack, .unique, .liveRadio:
                    content
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: trailingInset))
        .listRowSeparator(.hidden)
    }
    
    private var content: some View {
        Button {
            play()
        } label: {
            HStack {
                if let index {
                    Text(index, format: .number)
                        .font(.caption.monospacedDigit())
                        .frame(width: 30, alignment: .center)
                        .foregroundStyle(.secondary)
                }
                
                if !hideArtwork {
                    ContentArtworkView(content: item)
                        .frame(width: 50, height: 50)
                        .allowsHitTesting(!hideArtwork)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .lineLimit(1)
                            .foregroundStyle(isCurrentlyPlaying ? Color.accentColor : Color.primary)
                            .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
                        
                        Spacer(minLength: 0)

                        if item.content.service == .plex,
                           (plexRatingCache.ratings[item.id] ?? item.metadata?.userRating ?? 0) > 0 {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(MusicService.plex.brandColor)
                                .font(.caption2)
                        }

                        if item.metadata?.isExplicit == true {
                            Image(systemName: "e.square.fill")
                        }
                    }

                    Text(subtitleText)
                        .lineLimit(1)
                        .opacity(0.7)
                        .font(.footnote)
                }
                
                Spacer(minLength: 0)
                
                if adding == nil, !hideDetails, [.track, .favorite, .libraryTrack].contains(item.content.type) {
                    Menu {
                        PlayableMenuView(item: item)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            }
            .fontDesign(.rounded)
            .contentShape(Rectangle())
        }
        .swipeActions {
            if Self.swipeableTypes.contains(item.content.type) {
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
        .draggable(item) {
            Text(item.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background, in: .capsule)
                .contentShape(.dragPreview, .capsule)
        }
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
    
    private func play(position: QueuePosition? = nil) {
        if let add = adding?.add, add {
            adding?.content = item
            return
        }
        hideKeyboard()
        Task { @MainActor in
            let queueSong: ((GroupRoom) async throws -> Void) = { [replaceQueueByDefault, item, parent, index, total] group in
                if let parent, position == nil {
                    let finalPosition = position ?? QueuePosition.defaultPosition(
                        for: parent.content.type,
                        replaceQueueByDefault: replaceQueueByDefault
                    )
                    QueueManager.shared.addToQueue(item: QueueItem(playableContent: parent, group: group, position: finalPosition, index: index, total: total, showBanner: false))
                    Router.main.show(destination: .player(groupID: group.coordinatorID))
                    return
                }
                let finalPosition = position ?? QueuePosition.defaultPosition(
                    for: item.content.type,
                    replaceQueueByDefault: replaceQueueByDefault
                )
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: finalPosition, index: index, total: total, title: finalPosition.title))
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
