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
    @Environment(FavoriteRatingCache.self) private var favoriteRatingCache
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    @State private var audioService = AudioPlaybackService.shared

    let item: PlayableContent
    var parent: PlayableContent?
    var hideArtwork: Bool = false
    var hideDetails: Bool = false
    var hideContentType: Bool = false
    var index: Int? = nil
    var dismissOnComplete: Bool = false
    var total: Int = 1
    /// When set (track shown inside an editable playlist), adds a "Remove from Playlist" menu action.
    var onRemoveFromPlaylist: (() -> Void)? = nil
    
    private var isCurrentlyPlaying: Bool {
        guard let trackID = selectedGroupService?.group?.coordinatorRoom.track.trackID else { return false }
        // Compare both IDs decoded. The now-playing trackID is percent-encoded for some
        // services (e.g. Plex, whose ID is `clientID%3A3%3AratingKey` — the parser re-encodes
        // the colons via `.urlPathAllowed`), while `content.id` is already decoded here, so an
        // encoded-vs-decoded compare never matched and the Plex row never highlighted.
        return trackID.removingPercentEncoding == item.content.id.removingPercentEncoding
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

    private var isPreviewing: Bool {
        guard let url = item.previewURL else { return false }
        return audioService.isPreviewing(url)
    }

    private var previewProgress: Double {
        guard audioService.duration > 0 else { return 0 }
        return min(1, audioService.playbackProgress / audioService.duration)
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
        .onDisappear {
            if isPreviewing { AudioPlaybackService.shared.stopPreview() }
        }
    }
    
    private var content: some View {
        Button {
            if isPreviewing {
                HapticManager.shared.fireHaptic(.buttonPress)
                AudioPlaybackService.shared.stopPreview()
            } else {
                play()
            }
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
                        .frame(width: 50.scaled(by: UIDevice.current.userInterfaceIdiom.isCatalyst ? 1.4 : 1), height: 50.scaled(by: UIDevice.current.userInterfaceIdiom.isCatalyst ? 1.4 : 1))
                        .allowsHitTesting(!hideArtwork)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .lineLimit(1)
                            .foregroundStyle(isCurrentlyPlaying ? Color.accentColor : Color.primary)
                            .fontWeight(isCurrentlyPlaying ? .semibold : .regular)

                        Spacer(minLength: 0)

                        // Both self-hosted services carry favorite state on
                        // the row itself — Plex as a rating, Subsonic as the
                        // starred date — so neither needs a fetch to know.
                        if item.content.service == .plex || item.content.service == .subsonic,
                           (favoriteRatingCache.ratings[item.id] ?? item.metadata?.userRating ?? 0) > 0 {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(item.content.service.brandColor)
                                .font(.caption2)
                        }

                        // Kept on this device, coming down, or still in iCloud.
                        DownloadStateBadge(item: item)

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
                    // Keep the Menu in the tree at all times — swapping it out for the
                    // stop icon via if/else churns the Menu's identity and underlying
                    // gesture recognizers, which left taps landing mid-rebuild. Instead
                    // disable it while previewing (so taps fall through to the cell's
                    // stop handler) and overlay the stop icon on top.
                    Menu {
                        PlayableMenuView(item: item, onRemoveFromPlaylist: onRemoveFromPlaylist)
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("More Options for \(item.title)")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .opacity(isPreviewing ? 0 : 1)
                    }
                    .tint(.primary)
                    .disabled(isPreviewing)
                    .overlay {
                        if isPreviewing {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .fontDesign(.rounded)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                // Gated on isPreviewing so stopping removes the bar instantly,
                // instead of animating its width back down to zero.
                // No ignoresSafeArea: the bar lives inside a self-sizing List
                // cell, where safe-area-ignoring content can trigger UIKit's
                // layout feedback-loop trap (EXC_BREAKPOINT in
                // _UICollectionViewFeedbackLoopDebugger on iOS 26) — and the
                // 2pt row-bottom bar never meets a safe-area edge anyway.
                if isPreviewing {
                    Rectangle()
                        .foregroundStyle(.accent.gradient)
                        .frame(height: 2)
                        .scaleEffect(x: previewProgress, anchor: .leading)
                        .animation(.linear(duration: 0.3), value: previewProgress)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if Self.swipeableTypes.contains(item.content.type) {
                Button {
                    play(position: .next)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                .tint(.accentColor)
            }
        }
        .swipeActions(edge: .leading) {
            if let previewURL = item.previewURL,
               !previewURL.absoluteString.isEmpty,
               [.track, .libraryTrack].contains(item.content.type) {
                Button {
                    AudioPlaybackService.shared.preview(url: previewURL, streaming: item.content.service.streamsFullTrackPreview)
                } label: {
                    Label("Preview", systemImage: "music.note")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if adding == nil, !hideDetails {
                PlayableMenuView(item: item, onRemoveFromPlaylist: onRemoveFromPlaylist)
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
                PlayableMenuView(item: item, onRemoveFromPlaylist: onRemoveFromPlaylist)
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
                // `parent` is the playlist or album this row was tapped in.
                // The speaker takes it as the queue to play; the device
                // takes just the row, and this is what tells the player
                // where that row came from.
                await PlayDestinationRouter.play(item, position: defaultPosition, from: parent, queue: queueSong)
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
