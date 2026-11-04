import MusicSearchKit
import SonosKit
import SwiftUI

/// The player of the Mac's and an iPad's window (`DesktopShell`): one capsule
/// floating over the foot of the page, as Music's is. The transport with
/// shuffle and repeat, then what's playing with its progress under it, then
/// a speaker's volume, Play On and the queue.
///
/// Read through `PlaybackRoute.presented`, as the player is, so this
/// device and a Sonos group are one bar. The volume is a speaker's only:
/// the Mac's own is the system's, in the menu bar and on the keyboard.
struct LargePlayerBar: View {
    /// What it has room for, worked out from the window (`LargePlayerBarRooms`).
    let room: BarRoom
    /// Whether the window has anywhere to show the queue.
    let showsQueueToggle: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let scale = DesktopStyle.scale(typeSize)

        HStack(spacing: 12 * scale) {
            LargePlayerBarTransport(showsOrder: room == .everything || room == .noVolume, showsPrevious: room != .least)
            LargePlayerBarNowPlaying(showsProgress: room != .least)
                .frame(minWidth: room == .everything ? BarRoom.songWidthBesideVolume * scale : nil, maxWidth: 760 * scale)
                .frame(maxWidth: .infinity)
            // First in line for the width: the song gives way down to its
            // least, and only then the volume down to its own.
            LargePlayerBarActions(showsVolume: room == .everything, showsQueueToggle: showsQueueToggle)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14 * scale)
        .frame(maxHeight: .infinity)
        // A thick material rather than glass, which let bright covers
        // scrolling under it through too plainly to read the song over them.
        .background(.thickMaterial, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(DesktopStyle.panelEdge)
                .allowsHitTesting(false)
        }
    }
}

/// What the bar has room for: as it narrows the song gives way, then the
/// speaker's volume shrinks (both by layout, as the window moves), and only
/// then does the volume go (Play On still has it), then shuffle and repeat,
/// and last Previous and the song's progress, where a narrow window would
/// otherwise leave the title no room at all. A step rather than the width, so
/// a resize runs the bar again only as it crosses one.
enum BarRoom: Equatable {
    case everything, noVolume, essentials, least

    /// The least the song takes beside the volume, in base points. A long
    /// title scrolls, so it can be short of its text.
    static let songWidthBesideVolume: CGFloat = 220
    /// The least the volume takes, its name still readable.
    static let leastVolumeWidth: CGFloat = 170
    /// The volume at its full width.
    static let volumeWidth: CGFloat = 230

    /// From the bar's width in base points: the transport (212, 136 without
    /// shuffle and repeat), Play On and the queue (86), and the bar's spacing
    /// and margins (52), with room for the song.
    init(width: CGFloat) {
        let beside = 350 + 10 + Self.leastVolumeWidth + Self.songWidthBesideVolume
        self = switch width {
        case beside...: .everything
        case 580...: .noVolume
        case 440...: .essentials
        default: .least
        }
    }
}

/// What the bar has room for at a window's width, beside the queue and
/// without it. Both are known ahead, rather than measured from the bar, so
/// that a step goes with what caused it: the queue coming or going picks the
/// other one in its own update, and the step moves in the queue's animation,
/// where measured a moment later it landed in place while the queue still
/// slid, over the buttons on their way. A window being resized only changes
/// these, with no animation, as a Mac window's toolbar keeps up with the pointer.
struct LargePlayerBarRooms: Equatable {
    var besideQueue = BarRoom.everything
    var alone = BarRoom.everything

    init() {}

    /// All in points at the window's size, `scale` being `DesktopStyle.scale`.
    init(windowWidth: CGFloat, sidebarWidth: CGFloat, queueWidth: CGFloat, margin: CGFloat, scale: CGFloat, queueRoom: DesktopQueueRoom) {
        let barWidth = windowWidth - sidebarWidth - margin * 2
        // In the sidebar's place, the queue gives that room back.
        let widthBesideQueue = barWidth - queueWidth + (queueRoom == .inSidebarsPlace ? sidebarWidth : 0)
        besideQueue = BarRoom(width: widthBesideQueue / scale)
        alone = BarRoom(width: barWidth / scale)
    }
}

// MARK: - Transport

/// Shuffle, Previous, Play, Next and Repeat; a book's back 15 and forward
/// 30 s, with no shuffle or repeat. While a hand-off holds the bar on its
/// source they rest (`HeldPlaybackController`).
private struct LargePlayerBarTransport: View {
    /// Shuffle and repeat, where the bar has room for them.
    let showsOrder: Bool
    /// Previous, or a book's back 15 s, likewise.
    let showsPrevious: Bool

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

            if showsPrevious {
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
            }

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
private struct LargePlayerBarNowPlaying: View {
    /// The scrubber under the title, where there's room to use it.
    let showsProgress: Bool

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
                    .modifier(PlayerZoomSource())
            }
            .buttonStyle(.plain)
            .desktopHoverLift()
            .help("Show Player")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Button {
                        router.isPlayerPresented = true
                    } label: {
                        titles(item: item)
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
                } else if showsProgress {
                    PlayerScrubber(isInline: true)
                }
            }
        }
    }

    /// A title or artist too long for the bar scrolls (`MarqueeText`, which
    /// on the Mac does no work per frame: the bar is always on screen).
    private func titles(item: PlayableContent?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = item?.title {
                MarqueeText(title)
                    .font(.callout.weight(.semibold))
            } else {
                Text("Not Playing")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            subtitle(item: item)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            MarqueeText(subtitle, isSecondary: true)
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

/// Where an iPad's player zooms out of, as it does from the tab bar's mini
/// player. The Mac's slides up (`CueApp`), so it has no source.
private struct PlayerZoomSource: ViewModifier {
    @Environment(\.zoomNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        content
#else
        if let namespace {
            content.zoomSource(.miniPlayer, in: namespace)
        } else {
            content
        }
#endif
    }
}

// MARK: - Actions

/// A speaker group's volume while one plays, Play On, and the queue at
/// the bar's end. Play On on a speaker and the queue while it shows sit on
/// a soft accent circle. No lyrics: the player has them.
private struct LargePlayerBarActions: View {
    /// The speaker's volume, where the bar has room for it.
    let showsVolume: Bool
    /// The queue's button, where the window has somewhere to show it.
    let showsQueueToggle: Bool

    private var route: PlaybackRoute { .shared }
    @State private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The speaker it plays on, nothing on this Mac. Through a hand-off, where
    /// it's going.
    private var routeName: String? {
        if route.isHolding {
            return "Moving to \(route.group?.nameWithCount ?? ThisDevice.name)…"
        }
        return route.group?.nameWithCount
    }

    var body: some View {
        let controller = route.presented
        let scale = DesktopStyle.scale(typeSize)
        let isOnSpeaker = route.group != nil
        let showsQueue = appState.showsQueuePanel

        HStack(spacing: 6) {
            if showsVolume, let group = controller.group, !route.isHolding {
                LargePlayerBarVolume(group: group)
                    .frame(minWidth: BarRoom.leastVolumeWidth * scale, maxWidth: BarRoom.volumeWidth * scale)
                    .padding(.trailing, 4)
            }

            HStack(spacing: 6) {
                PlaybackRouteButton()
                    .font(.title3)
                    .tint(.primary)
                    .frame(width: 40 * scale, height: 40 * scale)
                    .accentCircle(isOn: isOnSpeaker)
                    .desktopHover(cornerRadius: 20 * scale)
                    .help("Play On")
                    // Under the button, as the phone's player has it; hung
                    // there rather than stacked, so it moves nothing beside it.
                    .overlay(alignment: .top) {
                        if let routeName {
                            Text(routeName)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(width: 120 * scale)
                                .offset(y: 40 * scale)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }

                if showsQueueToggle {
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
            // Lifted a little while there's a name, or it sits on the bar's edge.
            .offset(y: routeName == nil ? 0 : -3 * scale)
            .animation(.snappy, value: routeName == nil)
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
private struct LargePlayerBarVolume: View {
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
