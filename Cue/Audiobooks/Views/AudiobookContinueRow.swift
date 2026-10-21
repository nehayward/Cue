import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book in Continue Listening: its cover, title and author, how far in
/// (or how long, before it's started), and a round Play — Pause while it
/// plays. The rest of the row opens the book's page; a long press, its menu.
struct AudiobookContinueRow: View {
    let book: PlayableContent

    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared
    /// This row's Play is starting the book, read from its server first.
    @State private var isStarting = false

    private var route: PlaybackRoute { .shared }

    /// The book is loaded and the player has it.
    private var isLoaded: Bool {
        player.current?.book.isSameBook(as: book) == true && player.isPlayingBook(on: route.presented)
    }

    var body: some View {
        let progress = store.progress(for: book)
        let isPlaying = isLoaded && route.presented.isPlaying
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.navigate(to: .audiobookDetail(content: book))
            } label: {
                HStack(spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 3) {
                        // New York, a book's own face, for its title; the
                        // lines under it are rounded, set on themselves.
                        Text(book.title)
                            .font(.headline)
                            .fontDesign(.serif)
                            .lineLimit(2)
                        if !book.subtitle.isEmpty {
                            Text(book.subtitle)
                                .font(.subheadline)
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let progress {
                            progressLine(progress)
                                .fontDesign(.rounded)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(book.title)")

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task {
                    if isLoaded {
                        await route.presented.togglePlayback()
                    } else {
                        isStarting = true
                        await player.play(book)
                        isStarting = false
                    }
                }
            } label: {
                VStack {
                    if isStarting {
                        ProgressView()
                    } else {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .contentTransition(GroupMediaControlsView.playPauseTransition)
                    }
                }
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(isStarting || player.isLoading)
            .accessibilityLabel(isPlaying ? "Pause" : progress?.isStarted == true ? "Resume" : "Play")
        }
        // The book's menu (from the start, download or remove) is a long
        // press away, as on its other rows.
        .contextMenu {
            PlayableMenuView(item: book)
        }
    }

    private var cover: some View {
        ContentArtworkView(content: book, showMusicSource: false, preferredSize: 200, cornerRadius: 6)
            .frame(width: 72, height: 72)
            .overlay(alignment: .bottomTrailing) {
                // On this device: it plays with no network.
                if DownloadManager.shared.containerPresence(for: book) == .downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .font(.footnote)
                        .padding(4)
                        .accessibilityLabel("Downloaded")
                }
            }
    }

    /// How far in, as a bar and what's left ("15h 25m left"); the book's
    /// length before it's started.
    @ViewBuilder
    private func progressLine(_ progress: AudiobookProgress) -> some View {
        if progress.isStarted, let fraction = progress.fraction {
            HStack(spacing: 10) {
                // The bar gives way to the time, which keeps to one line.
                AudiobookProgressBar(fraction: fraction)
                    .frame(minWidth: 24, maxWidth: 72)
                if let remaining = AudiobookFormat.remaining(progress) {
                    Text(remaining)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } else if progress.duration > 0 {
            Text(AudiobookFormat.duration(progress.duration))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - A row of covers
