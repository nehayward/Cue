import CloudStorage
import MusicSearchKit
import Defaults
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct PlayableContentView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router: Router?
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    var item: PlayableContent
    var hideArtwork: Bool = false
    var hideDetails: Bool = false

    var body: some View {
        if hideDetails {
            content
        } else if let add = adding?.add, add {
            content
        } else {
            switch item.content.type {
            case .playlist, .album, .libraryPlaylist, .libraryAlbum:
                NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService?.group)) {
                    content
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden, edges: .all)
            case .artist, .libraryArtist:
                NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService?.group)) {
                    content
                }
            case .track, .favorite, .radio, .libraryTrack:
                content
            }
        }
    }

    private var content: some View {
        Button {
            play(replaceQueue: item.content.type == .playlist)
        } label: {
            HStack {
                if !hideArtwork {
                    ContentArtworkView(content: item)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text(item.title)
                            .lineLimit(1)
                        if let isExplicit = item.metadata?.isExplicit, isExplicit {
                            Image(systemName: "e.square.fill")
                        }
                    }
                    HStack(spacing: 0) {
                        Text("\(item.content.type.title)\(item.subtitle.isEmpty ? "" : " • \(item.subtitle)")")
                            .truncationMode(.head)

                        // MARK: Add back when you normalize duration to seconds
//                        if let duration = item.metadata?.duration, duration.components.seconds != 0 {
//                            Text(" • ")
//                            Text(duration, format: .time(pattern: .minuteSecond))
//                        }
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
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .fontDesign(.rounded)
        }
        .swipeActions {
            if playHistoryService.history.contains(item) {
                Button(role: .destructive) {
                    playHistoryService.history.remove(item)
                } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if adding == nil, !hideDetails {
                PlayableMenuView(item: item)
            }
        }
        .draggable(item)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .all)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: trailingInset))
    }

    private func play(position: QueuePosition = .now, replaceQueue: Bool = false) {
        if let add = adding?.add, add {
            adding?.content = item
            return
        }
        hideKeyboard()
        Task { @MainActor in
            let queueSong: ((GroupRoom) async throws -> Void) = { group in
                HapticManager.shared.fireHaptic(.buttonPress)
                do {
                    try await sonosService.queue(playable: item, group: group, position: position, replaceQueue: replaceQueue)
                    await sonosService.play(ip: group.coordinatorRoom.ip)
                    playHistoryService.history.remove(item)
                    playHistoryService.history.insert(item, at: 0)
                } catch {
                    alertService.showAlert(with: "Please authorize \(item.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
                }
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
