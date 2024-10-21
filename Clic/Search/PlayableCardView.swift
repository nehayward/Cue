import CloudStorage
import MusicSearchKit
import Defaults
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Glur
import Defaults

struct PlayableCardView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    var item: PlayableContent
    var hideArtwork: Bool = false
    var hideAction: Bool = false

    var body: some View {
        Group {
            if let add = adding?.add, add {
                content
            } else {
                if !hideAction {
                    switch item.content.type {
                    case .playlist, .album, .libraryPlaylist, .libraryAlbum:
                        NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                            content
                        }
                    case .artist, .libraryArtist:
                        NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                            content
                        }
                    case .track, .favorite, .radio:
                        Button {
                            play()
                        } label: {
                            content
                        }
                    case .libraryTrack:
                        content
                    }
                } else {
                    Button {
                        play()
                    } label: {
                        content
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .all)
        .overlay(alignment: .topTrailing) {
            if adding == nil && !hideAction {
                Menu {
                    PlayableMenuView(item: item)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                        .bold()
                        .shadow(radius: 4)
                        .frame(maxWidth: 44, maxHeight: 44)
                }
                .frame(maxWidth: 44, maxHeight: 44)
            }
        }
    }

    private var content: some View {
        ContentArtworkView(content: item, showMusicSource: false, preferredSize: 300)
            .aspectRatio(contentMode: .fit)
            .glur(radius: 30, // The total radius of the blur effect when fully applied.
                  offset: 0.6, // The distance from the view's edge to where the effect begins, relative to the view's size.
                  interpolation: 0.3, // The distance from the offset to where the effect is fully applied, relative to the view's size.
                  direction: .down // The direction in which the effect is applied.
            )
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
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .contextMenu {
                if adding == nil {
                    PlayableMenuView(item: item)
                }
            }
            .draggable(item)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 20)
    }


    private func play(position: QueuePosition = .now, replaceQueue: Bool = false) {
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
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong))
                return
            }
            try await queueSong(group)
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
