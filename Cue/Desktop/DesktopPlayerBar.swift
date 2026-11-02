import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The player's cards along the bottom of the Mac window (`DesktopShell`),
/// after DaftMusic's: what's playing under the sidebar, the transport, the
/// scrubber, Play On with the speaker's volume, lyrics and the queue, and
/// under the queue's card its summary with shuffle and repeat.
///
/// Read through `PlaybackRoute.presented`, as the player is, so this
/// device and a Sonos group are one bar. The volume is a speaker's only:
/// the Mac's own is the system's, in the menu bar and on the keyboard.
struct DesktopPlayerBar: View {
    let sidebarWidth: CGFloat
    let queueWidth: CGFloat
    let showsQueueSummary: Bool

    var body: some View {
        HStack(spacing: DesktopStyle.gap) {
            DesktopNowPlayingCard()
                .frame(width: sidebarWidth)
            DesktopTransportCard()
            DesktopScrubberCard()
                .frame(maxWidth: .infinity)
            DesktopActionsCard()
            if showsQueueSummary {
                DesktopQueueSummaryCard()
                    .frame(width: queueWidth)
            }
        }
    }
}

/// A bar card's shape: its content in a row, centred in the bar's height.
private struct BarCard<Content: View>: View {
    var horizontalPadding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxHeight: .infinity)
        .background(DesktopStyle.card, in: .rect(cornerRadius: DesktopStyle.cornerRadius))
    }
}

// MARK: - Now playing

/// The song: its cover, title and artist, opening the player, and the like
/// button where its service has one. On a speaker, the group's name under
/// it; through a hand-off, where it's going.
private struct DesktopNowPlayingCard: View {
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

        BarCard(horizontalPadding: 10) {
            Button {
                router.isPlayerPresented = true
            } label: {
                HStack(spacing: 12) {
                    artwork(item: item, group: group)
                    VStack(alignment: .leading, spacing: 2) {
                        // Cut short rather than scrolled: the bar is always
                        // on screen, and a marquee redraws every frame while
                        // it moves. The whole title is the tooltip.
                        if let title = item?.title {
                            Text(title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .help(title)
                        } else {
                            Text("Not Playing")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        subtitle(item: item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if route.isHolding || group != nil {
                            Label(route.isHolding ? "Moving to \(route.group?.nameWithCount ?? "This Mac")…" : group?.nameWithCount ?? "", systemImage: "hifispeaker.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color("Accent"))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .desktopHover(cornerRadius: 14)
            .help("Show Player")

            likeButton(item: item, group: group)
        }
    }

    @ViewBuilder
    private func artwork(item: PlayableContent?, group: GroupRoom?) -> some View {
        Group {
            if group != nil, route.isSwitching, !route.isHolding {
                ProgressView()
            } else if let item {
                ContentArtworkView(content: item, showMusicSource: false)
                    .clipShape(.rect(cornerRadius: 9))
            } else {
                Image(systemName: group == nil ? "music.note" : "hifispeaker.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: .rect(cornerRadius: 9))
            }
        }
        .frame(width: scaled(52), height: scaled(52))
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
                    .frame(width: scaled(36), height: scaled(36))
            } else if let song = local.onAirMatch {
                LikeButtonView(content: song)
                    .id(song.content.id)
                    .frame(width: scaled(36), height: scaled(36))
            } else if let item = local.nowPlaying, item.content.service.supportsFavoriteTrack {
                LikeButtonView(content: item)
                    .frame(width: scaled(36), height: scaled(36))
            }
        }
    }
}

// MARK: - Transport

/// Previous, Play and Next; a book's back 15 and forward 30 s. While a
/// hand-off holds the bar on its source they rest
/// (`HeldPlaybackController`).
private struct DesktopTransportCard: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        let controller = route.presented

        BarCard(horizontalPadding: 8) {
            Button {
                Task { await PlayerCommands.previous() }
            } label: {
                Image(systemName: PlayerCommands.previousSymbol)
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 44))
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
            .buttonStyle(DesktopIconButtonStyle(side: 52))
            .disabled(!controller.isActive)
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
            .help(controller.isPlaying ? "Pause" : "Play")

            Button {
                Task { await PlayerCommands.next() }
            } label: {
                Image(systemName: PlayerCommands.nextSymbol)
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 44))
            .disabled(!PlayerCommands.canGoNext)
            .accessibilityLabel(PlayerCommands.nextTitle)
            .help(PlayerCommands.nextTitle)
        }
    }
}

// MARK: - Scrubber

/// The player's own scrubber, in one row (`PlayerScrubber`); a station's
/// word for having no end.
private struct DesktopScrubberCard: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        let controller = route.presented

        BarCard(horizontalPadding: 22) {
            if controller.nowPlayingDisplay != nil, controller.duration.isZero || !controller.duration.isFinite {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                PlayerScrubber(isInline: true)
            }
        }
    }
}

// MARK: - Actions

/// Play On, a speaker's volume while one plays, lyrics and the queue.
private struct DesktopActionsCard: View {
    private var route: PlaybackRoute { .shared }
    @State private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let controller = route.presented
        let isBook = PlayerCommands.isBook

        BarCard(horizontalPadding: 8) {
            PlaybackRouteButton()
                .font(.title3)
                .frame(width: 44 * DesktopStyle.scale(typeSize), height: 44 * DesktopStyle.scale(typeSize))
                .desktopHover(cornerRadius: 22)
                .help("Play On")

            if let group = controller.group, !route.isHolding {
                DesktopSpeakerVolume(group: group)
            }

            Button {
                // The lyrics are looked up while the player is open, so the
                // button opens it on them.
                UserDefaults.standard.set(true, forKey: AppStorageKeys.lyricsShown)
                Router.main.isPlayerPresented = true
            } label: {
                Image(systemName: isBook ? "captions.bubble" : "quote.bubble")
                    .font(.title3)
            }
            .buttonStyle(DesktopIconButtonStyle(side: 44))
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
            .buttonStyle(DesktopIconButtonStyle(side: 44))
            .accessibilityLabel(QueueToggleIcon.title(isShown: appState.showsQueuePanel))
            .accessibilityAddTraits(appState.showsQueuePanel ? .isSelected : [])
            .help("\(QueueToggleIcon.title(isShown: appState.showsQueuePanel)) (⌥⌘0)")
        }
    }
}

/// A Sonos group's volume: the speaker glyph, which mutes it, and the
/// group's slider (`VolumeControlView`, which sends the levels).
private struct DesktopSpeakerVolume: View {
    @Bindable var group: GroupRoom
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VolumeControlView(group: group, immediateDrag: true)
            .frame(width: 200 * DesktopStyle.scale(typeSize))
            .padding(.horizontal, 4)
    }
}

// MARK: - Queue summary

/// How long the queue is and where in it playback is, with shuffle and
/// repeat; a book's title and what's left of it.
private struct DesktopQueueSummaryCard: View {
    private var route: PlaybackRoute { .shared }

    var body: some View {
        let controller = route.presented
        let isBook = PlayerCommands.isBook

        BarCard(horizontalPadding: 18) {
            VStack(alignment: .leading, spacing: 2) {
                if isBook {
                    Text(AudiobookPlayer.shared.current?.book.title ?? "Audiobook")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    AudiobookTimeLeft(isCompact: true)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if controller.queueCount > 0 {
                    Text(controller.queueCount == 1 ? "1 Song" : "\(controller.queueCount) Songs")
                        .font(.callout.weight(.semibold))
                    if controller.queuePosition > 0 {
                        Text("Playing \(controller.queuePosition) of \(controller.queueCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing Queued")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isBook {
                Button {
                    Task { await controller.setRepeatMode(controller.repeatMode.next) }
                } label: {
                    Image(systemName: controller.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.title3)
                        .foregroundStyle(controller.repeatMode == .off ? AnyShapeStyle(.primary) : AnyShapeStyle(Color("Accent")))
                }
                .buttonStyle(DesktopIconButtonStyle(side: 40))
                .disabled(!controller.isActive || controller.queueCount == 0)
                .accessibilityLabel("Repeat")
                .accessibilityValue(repeatDescription(controller.repeatMode))
                .help("Repeat: \(repeatDescription(controller.repeatMode))")

                Button {
                    Task { await controller.setShuffle(!controller.isShuffled) }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundStyle(controller.isShuffled ? AnyShapeStyle(Color("Accent")) : AnyShapeStyle(.primary))
                }
                .buttonStyle(DesktopIconButtonStyle(side: 40))
                .disabled(!controller.isActive || controller.queueCount == 0)
                .accessibilityLabel("Shuffle")
                .accessibilityValue(controller.isShuffled ? "On" : "Off")
                .help(controller.isShuffled ? "Shuffle: On" : "Shuffle: Off")
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
