import CloudStorage
import Defaults
import MusicKit
import MusicSearchKit
import OrderedCollections
import SonosKit
import SwiftUI

struct PlayableContentRowView: View {
    private static let swipeableTypes: Set<ContentType> = [.playlist, .libraryPlaylist, .album, .track, .libraryTrack, .libraryAlbum]
    
    @Environment(Router.self) private var router: Router?
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    @State private var averageColor: Color?

    private var displayColor: Color? {
        if let averageColor { return averageColor }
        if let cached = UIImage.cachedAverageColor(forKey: item.imageKey) {
            return Color(uiColor: cached)
        }
        return nil
    }

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
        return "\(item.subtitle)"
    }
    
    private var shouldShowPlainContent: Bool {
        hideDetails || item.content.service == .unknown || (adding?.add == true && !item.content.type.isArtist)
    }
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Menu {
           PlayableMenuView(item: item)
        } label: {
            HStack {
                if let index {
                    Text(index, format: .number)
                        .font(.caption.monospacedDigit())
                        .frame(width: 30, alignment: .center)
                        .foregroundStyle(.secondary)
                }
                
                if !hideArtwork {
                    ContentArtworkView(content: item) { color in
                        averageColor = color
                    }
                    .frame(width: 50, height: 50)
                    .allowsHitTesting(!hideArtwork)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if item.metadata?.isExplicit == true {
                            Image(systemName: "e.square.fill")
                        }
                    }
                    
                    Text(subtitleText)
                        .lineLimit(1)
                        .opacity(0.80)
                        .font(.caption)
                }
            }
            .fontDesign(.rounded)
            .contentShape(.rect)
            .background {
                if let displayColor {
                    RoundedRectangle(cornerRadius: 4)
                        .foregroundStyle(displayColor.opacity(0.2))
                }
            }
        } primaryAction: {
            switch item.content.type {
            case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
                router?.navigate(to: .mediaDetail(content: item, group: selectedGroupService?.group))
            case .artist, .libraryArtist:
                router?.navigate(to: .artistDetail(content: item, group: selectedGroupService?.group))
            case .folder:
                router?.navigate(to:  .folderBrowse(item: item, title: item.title))
            case .track, .favorite, .radio, .songRadio, .artistRadio, .libraryTrack, .unique, .liveRadio:
                play()
            }
        }
        .foregroundStyle(.primary)
    }
    
    private var folderContent: some View {
        Label {
            Text(item.title)
            Text(item.content.type.title)
                .font(.caption)
                .opacity(0.8)
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
            let defaultPosition = position ?? QueuePosition.defaultPosition(
                for: (parent ?? item).content.type,
                replaceQueueByDefault: replaceQueueByDefault
            )
            let queueSong: ((GroupRoom, QueuePosition) async throws -> Void) = { [item, parent, index, total] group, selectedPosition in
                if let parent, position == nil {
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

//#Preview {
//    ScrollView {
//        HStack {
//            PlayableContentRowView(item: .bazAlbum)
//            PlayableContentRowView(item: .harry)
//        }
//    }
//    .preferredColorScheme(.dark)
//    
//}
