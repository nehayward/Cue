import MusicSearchKit
import SonosKit
import SwiftUI

/// The player of the Mac window (`DesktopShell`): one glass capsule
/// floating over the foot of the page, as Music's is. The transport with
/// shuffle and repeat, then what's playing with its progress under it, then
/// a speaker's volume, Play On and the queue.
///
/// Read through `PlaybackRoute.presented`, as the player is, so this
/// device and a Sonos group are one bar. The volume is a speaker's only:
/// the Mac's own is the system's, in the menu bar and on the keyboard.
struct DesktopPlayerBar: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var room = BarRoom.everything

    var body: some View {
        let scale = DesktopStyle.scale(typeSize)

        HStack(spacing: 12 * scale) {
            DesktopTransport(showsOrder: room != .essentials)
            DesktopNowPlaying()
                .frame(maxWidth: 760 * scale)
                .frame(maxWidth: .infinity)
            DesktopBarActions(showsVolume: room == .everything)
        }
        .padding(.horizontal, 14 * scale)
        .frame(maxHeight: .infinity)
        .playerBarGlass()
        .onGeometryChange(for: BarRoom.self) { [scale] in BarRoom(width: $0.size.width / scale) } action: { room = $0 }
    }
}

/// What the bar has room for: beside the queue on a smaller window
/// the page is narrow, so the speaker's volume goes first (Play On still
/// has it), then shuffle and repeat. A step rather than the width, so a
/// resize runs the bar again only as it crosses one.
private enum BarRoom {
    case everything, noVolume, essentials

    /// From the bar's width in base points: what each set takes, with
    /// room for a title beside it.
    init(width: CGFloat) {
        self = switch width {
        case 850...: .everything
        case 610...: .noVolume
        default: .essentials
        }
    }
}

private extension View {
    /// Glass, as the page shows through it while it scrolls under. The
    /// regular kind, as Music's bar has: the clear one let the page through
    /// too plainly to read the bar over it.
    @ViewBuilder
    func playerBarGlass() -> some View {
#if !os(visionOS)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.thickMaterial, in: .capsule)
        }
#else
        background(.thickMaterial, in: .capsule)
#endif
    }
}

// MARK: - Transport

/// Shuffle, Previous, Play, Next and Repeat; a book's back 15 and forward
/// 30 s, with no shuffle or repeat. While a hand-off holds the bar on its
/// source they rest (`HeldPlaybackController`).
private struct DesktopTransport: View {
    /// Shuffle and repeat, where the bar has room for them.
    let showsOrder: Bool

    private var route: PlaybackRoute { .shared }

    var body: some View {
        let controller = route.presented
        let showsOrder = showsOrder && !PlayerCommands.isBook
        let canChangeOrder = controller.isActive && controller.queueCount > 0

        HStack(spacing: 2) {
            if showsOrder {
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

            if showsOrder {
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

    /// A title or artist too long for the bar scrolls, as the player's
    /// title does (`MarqueeText`: two copies moved by layout, no shader,
    /// and no frames while Cue is hidden or minimised). The speaker's name
    /// keeps its room and the artist scrolls beside it.
    private func titles(item: PlayableContent?, group: GroupRoom?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = item?.title {
                MarqueeText(title)
                    .font(.callout.weight(.semibold))
            } else {
                Text("Not Playing")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if route.isHolding || group != nil {
                    Label(route.isHolding ? "Moving to \(route.group?.nameWithCount ?? ThisDevice.name)…" : group?.nameWithCount ?? "", systemImage: "hifispeaker.fill")
                        .foregroundStyle(Color("Accent"))
                        .fontWeight(.semibold)
                        .layoutPriority(1)
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
            MarqueeText(subtitle)
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

/// A speaker group's volume while one plays, Play On, and the queue at
/// the bar's end. Play On on a speaker and the queue while it shows sit on
/// a soft accent circle. No lyrics: the player has them.
private struct DesktopBarActions: View {
    /// The speaker's volume, where the bar has room for it.
    let showsVolume: Bool

    private var route: PlaybackRoute { .shared }
    @State private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let controller = route.presented
        let scale = DesktopStyle.scale(typeSize)
        let isOnSpeaker = route.group != nil
        let showsQueue = appState.showsQueuePanel

        HStack(spacing: 6) {
            if showsVolume, let group = controller.group, !route.isHolding {
                DesktopSpeakerVolume(group: group)
                    .frame(width: 230 * scale)
                    .padding(.trailing, 4)
            }

            PlaybackRouteButton()
                .font(.title3)
                .tint(.primary)
                .frame(width: 40 * scale, height: 40 * scale)
                .accentCircle(isOn: isOnSpeaker)
                .desktopHover(cornerRadius: 20 * scale)
                .help("Play On")

            Button {
                withAnimation(.snappy) {
                    appState.showsQueuePanel.toggle()
                }
            } label: {
                QueueToggleIcon()
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 40))
            .accentCircle(isOn: showsQueue)
            .accessibilityLabel(QueueToggleIcon.title(isShown: showsQueue))
            .accessibilityAddTraits(showsQueue ? .isSelected : [])
            .help("\(QueueToggleIcon.title(isShown: showsQueue)) (⌥⌘0)")
        }
    }
}

private extension View {
    /// Behind a bar button that's on: a soft wash of the accent, faded and
    /// grown in with the button's change rather than appearing at once,
    /// and light enough that the glyph on it still reads. A tinted glass
    /// circle came and went with no animation and drowned the glyph.
    func accentCircle(isOn: Bool) -> some View {
        background {
            Circle()
                .fill(Color("Accent").opacity(0.3))
                .scaleEffect(isOn ? 1 : 0.6)
                .opacity(isOn ? 1 : 0)
                .animation(.snappy, value: isOn)
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
