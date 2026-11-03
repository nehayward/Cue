import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The player along the bottom of the Mac window (`DesktopShell`): one
/// rounded bar, as Music's is. The transport with shuffle and repeat, then
/// what's playing with its progress under it, then lyrics, the queue, Play
/// On and a speaker's volume.
///
/// Read through `PlaybackRoute.presented`, as the player is, so this
/// device and a Sonos group are one bar. The volume is a speaker's only:
/// the Mac's own is the system's, in the menu bar and on the keyboard.
struct DesktopPlayerBar: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let scale = DesktopStyle.scale(typeSize)

        HStack(spacing: 12 * scale) {
            DesktopTransport()
            DesktopNowPlaying()
                .frame(maxWidth: 760 * scale)
                .frame(maxWidth: .infinity)
            DesktopBarActions()
        }
        .padding(.horizontal, 14 * scale)
        .frame(maxHeight: .infinity)
        .background(DesktopStyle.card, in: .capsule)
    }
}

// MARK: - Transport

/// Shuffle, Previous, Play, Next and Repeat; a book's back 15 and forward
/// 30 s, with no shuffle or repeat. While a hand-off holds the bar on its
/// source they rest (`HeldPlaybackController`).
private struct DesktopTransport: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        let controller = route.presented
        let isBook = PlayerCommands.isBook
        let canChangeOrder = controller.isActive && controller.queueCount > 0

        HStack(spacing: 2) {
            if !isBook {
                Button {
                    Task { await controller.setShuffle(!controller.isShuffled) }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.body)
                        .foregroundStyle(controller.isShuffled ? AnyShapeStyle(Color("Accent")) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(DesktopIconButtonStyle(side: 36))
                .disabled(!canChangeOrder)
                .accessibilityLabel("Shuffle")
                .accessibilityValue(controller.isShuffled ? "On" : "Off")
                .help(controller.isShuffled ? "Shuffle: On" : "Shuffle: Off")
            }

            Button {
                Task { await PlayerCommands.previous() }
            } label: {
                Image(systemName: PlayerCommands.previousSymbol)
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 42))
            .disabled(!PlayerCommands.canGoPrevious)
            .accessibilityLabel(PlayerCommands.previousTitle)
            .help(PlayerCommands.previousTitle)

            Button {
                Task { await PlayerCommands.togglePlayback() }
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .contentTransition(GroupMediaControlsView.animatesPlayPause ? .symbolEffect(.replace) : .identity)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 48))
            .disabled(!controller.isActive)
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
            .help(controller.isPlaying ? "Pause" : "Play")

            Button {
                Task { await PlayerCommands.next() }
            } label: {
                Image(systemName: PlayerCommands.nextSymbol)
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 42))
            .disabled(!PlayerCommands.canGoNext)
            .accessibilityLabel(PlayerCommands.nextTitle)
            .help(PlayerCommands.nextTitle)

            if !isBook {
                Button {
                    Task { await controller.setRepeatMode(controller.repeatMode.next) }
                } label: {
                    Image(systemName: controller.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.body)
                        .foregroundStyle(controller.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color("Accent")))
                }
                .buttonStyle(DesktopIconButtonStyle(side: 36))
                .disabled(!canChangeOrder)
                .accessibilityLabel("Repeat")
                .accessibilityValue(repeatDescription(controller.repeatMode))
                .help("Repeat: \(repeatDescription(controller.repeatMode))")
            }
        }
    }

    private func repeatDescription(_ mode: LocalPlaybackService.RepeatMode) -> String {
        switch mode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }
}

// MARK: - Now playing

/// The song: its cover, title and artist, opening the player, the like
/// button where its service has one, and its progress under them. On a
/// speaker, the group's name; through a hand-off, where it's going.
private struct DesktopNowPlaying: View {
    private var route: PlaybackRoute { .shared }
    @State private var router = Router.main
    @Environment(\.dynamicTypeSize) private var typeSize

    private func scaled(_ value: CGFloat) -> CGFloat {
        (value * DesktopStyle.scale(typeSize)).rounded()
    }

    var body: some View {
        let controller = route.presented
        let group = controller.group
        let item = controller.nowPlayingDisplay

        HStack(spacing: 12) {
            Button {
                router.isPlayerPresented = true
            } label: {
                artwork(item: item, group: group)
            }
            .buttonStyle(.plain)
            .desktopHoverLift()
            .help("Show Player")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Button {
                        router.isPlayerPresented = true
                    } label: {
                        titles(item: item, group: group)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(item?.title ?? "Show Player")

                    likeButton(item: item, group: group)
                }

                if item != nil, controller.duration.isZero || !controller.duration.isFinite {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    PlayerScrubber(isInline: true)
                }
            }
        }
    }

    /// Cut short rather than scrolled: the bar is always on screen, and a
    /// marquee redraws every frame while it moves.
    private func titles(item: PlayableContent?, group: GroupRoom?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = item?.title {
                Text(title)
                    .font(.callout.weight(.semibold))
            } else {
                Text("Not Playing")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if route.isHolding || group != nil {
                    Label(route.isHolding ? "Moving to \(route.group?.nameWithCount ?? "This Mac")…" : group?.nameWithCount ?? "", systemImage: "hifispeaker.fill")
                        .foregroundStyle(Color("Accent"))
                        .fontWeight(.semibold)
                }
                subtitle(item: item)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func artwork(item: PlayableContent?, group: GroupRoom?) -> some View {
        VStack {
            if group != nil, route.isSwitching, !route.isHolding {
                ProgressView()
            } else if let item {
                ContentArtworkView(content: item, showMusicSource: false)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                Image(systemName: group == nil ? "music.note" : "hifispeaker.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
            }
        }
        .frame(width: scaled(50), height: scaled(50))
    }

    @ViewBuilder
    private func subtitle(item: PlayableContent?) -> some View {
        if PlayerCommands.isBook {
            AudiobookTimeLeft(prefix: AudiobookPlayer.shared.current?.book.subtitle, isCompact: true)
        } else if let subtitle = item?.subtitle, !subtitle.isEmpty {
            Text(subtitle)
        }
    }

    /// The player's like button, by its rule: a speaker's track; on this
    /// device the song on air while a station plays and Apple Music has
    /// it, else the song where its service can like it.
    @ViewBuilder
    private func likeButton(item: PlayableContent?, group: GroupRoom?) -> some View {
        let local = LocalPlaybackService.shared
        if !route.isHolding {
            if let group {
                LikeButtonView(group: group)
                    .frame(width: scaled(28), height: scaled(28))
            } else if let song = local.onAirMatch {
                LikeButtonView(content: song)
                    .id(song.content.id)
                    .frame(width: scaled(28), height: scaled(28))
            } else if let item = local.nowPlaying, item.content.service.supportsFavoriteTrack {
                LikeButtonView(content: item)
                    .frame(width: scaled(28), height: scaled(28))
            }
        }
    }
}

// MARK: - Actions

/// Lyrics, the queue, Play On and a speaker group's volume while one
/// plays.
private struct DesktopBarActions: View {
    private var route: PlaybackRoute { .shared }
    @State private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let controller = route.presented
        let isBook = PlayerCommands.isBook
        let scale = DesktopStyle.scale(typeSize)

        HStack(spacing: 2) {
            Button {
                // The lyrics are looked up while the player is open, so the
                // button opens it on them.
                UserDefaults.standard.set(true, forKey: AppStorageKeys.lyricsShown)
                Router.main.isPlayerPresented = true
            } label: {
                Image(systemName: isBook ? "captions.bubble" : "quote.bubble")
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 40))
            .disabled(controller.nowPlayingDisplay == nil)
            .accessibilityLabel(isBook ? "Transcript" : "Lyrics")
            .help(isBook ? "Transcript" : "Lyrics")

            Button {
                withAnimation(.snappy) {
                    appState.showsQueuePanel.toggle()
                }
            } label: {
                QueueToggleIcon()
                    .font(.title3)
                    .foregroundStyle(appState.showsQueuePanel ? AnyShapeStyle(Color("Accent")) : AnyShapeStyle(.primary))
            }
            .buttonStyle(DesktopIconButtonStyle(side: 40))
            .accessibilityLabel(QueueToggleIcon.title(isShown: appState.showsQueuePanel))
            .accessibilityAddTraits(appState.showsQueuePanel ? .isSelected : [])
            .help("\(QueueToggleIcon.title(isShown: appState.showsQueuePanel)) (⌥⌘0)")

            PlaybackRouteButton()
                .font(.title3)
                .frame(width: 40 * scale, height: 40 * scale)
                .desktopHover(cornerRadius: 20 * scale)
                .help("Play On")

            if let group = controller.group, !route.isHolding {
                DesktopSpeakerVolume(group: group)
                    .frame(width: 230 * scale)
                    .padding(.leading, 6)
            }
        }
    }
}

/// A Sonos group's volume as the Play On sheet draws it: the group on a
/// capsule its level fills, dragged sideways to set it (`VolumeRouteRow`),
/// its menu muting every room.
private struct DesktopSpeakerVolume: View {
    let group: GroupRoom
    @State private var volumes = SpeakerVolumeWriter()

    var body: some View {
        let isMuted = group.isAllMuted

        VolumeRouteRow(
            title: group.nameWithCount,
            icon: .speakers(group.rooms.count),
            mark: .empty,
            // A fixed-output coordinator ignores volume: nothing to drag.
            level: group.coordinatorRoom.isOutputFixed ? nil : group.groupVolume / 100,
            isMuted: isMuted,
            listIsSettled: true,
            onLevel: { volumes.set(group, to: $0 * 100) }
        )
        .contextMenu {
            Button {
                group.setAllMuted(!isMuted)
            } label: {
                Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
        }
        .help("\(group.nameWithCount): drag for its volume")
    }
}
