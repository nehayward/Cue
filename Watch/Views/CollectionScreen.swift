import SwiftUI
import WatchSync

/// An album, playlist or artist on the watch, or the songs added on their
/// own: Play and Shuffle (the downloaded songs from the watch, the rest
/// streamed), and each song with where its download stands.
struct CollectionScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var playOn = PlayOn()
    let route: LibraryRoute

    private var picks: [WatchPick] {
        switch route {
        case let .pick(key): store.picks.pick(key: key).map { [$0] } ?? []
        case .songs: store.picks.items.filter { $0.kind == .song }
        }
    }

    var body: some View {
        let picks = self.picks
        let songs = store.songs(in: picks.map(\.key))
        let playable = songs.filter { store.isPlayable($0.key) }
        if picks.isEmpty {
            Text("Removed from this watch")
                .foregroundStyle(.secondary)
        } else {
            List {
                Section {
                    header(for: picks)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)

                    HStack {
                        Button {
                            playOn.play(songs)
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Play")
                        .primaryHandGesture()
                        Button {
                            playOn.play(songs, shuffled: true)
                        } label: {
                            Image(systemName: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Shuffle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(songs.isEmpty)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(songs) { song in
                        Button {
                            playOn.play(songs, startingAt: song.key)
                        } label: {
                            SongStateRow(song: song, item: store.item(for: song.key), isCurrent: player.current?.key == song.key)
                        }
                        .swipeActions {
                            if route == .songs {
                                Button(role: .destructive) {
                                    store.remove(key: song.pick.key)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                } footer: {
                    footer(picks: picks, songs: songs, playable: playable)
                }

                if case let .pick(key) = route {
                    Section {
                        Button(role: .destructive) {
                            store.remove(key: key)
                            dismiss()
                        } label: {
                            Text("Remove from Watch")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(route == .songs ? "Songs" : picks[0].title)
            .playOnSheet(playOn)
        }
    }

    @ViewBuilder
    private func header(for picks: [WatchPick]) -> some View {
        if route != .songs, let pick = picks.first {
            VStack(spacing: 4) {
                ArtworkView(url: pick.artworkURL)
                    .frame(width: 80, height: 80)
                Text(pick.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !pick.subtitle.isEmpty {
                    Text(pick.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(picks: [WatchPick], songs: [WatchSong], playable: [WatchSong]) -> some View {
        let keys = picks.map(\.key)
        if keys.contains(where: { store.lookingUp.contains($0) }) {
            Text("Looking up on the server…")
        } else if keys.contains(where: { store.unreachable.contains($0) }) {
            Text("Couldn't reach the server. Cue tries again the next time you open it.")
        } else if playable.count < songs.count {
            Text("\(playable.count) of \(songs.count) songs on this watch; the rest stream when they play. Fast Download fetches them over Wi‑Fi.")
        } else if !songs.isEmpty, route != .songs {
            Text("\(songs.count == 1 ? "1 song" : "\(songs.count) songs") • \(ByteCountFormatter.string(fromByteCount: store.bytesUsed(by: songs), countStyle: .file))")
        } else if route == .songs {
            Text("Swipe a song to take it off this watch.")
        }
    }
}

/// A song on the watch, with where its download stands.
struct SongStateRow: View {
    let song: WatchSong
    let item: WatchDownloadStore.Item?
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading) {
                Text(song.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(song.artist)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            stateIcon
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item?.state {
        case .completed:
            if let size = item?.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .downloading:
            // A converted stream doesn't say how big it is, so there's no
            // fraction to show for it.
            if let item, item.bytesReceived > 0, item.bytesExpected > 0 {
                ProgressRing(fraction: item.progress)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "arrow.down.circle.dotted")
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case .queued, nil:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        }
    }
}
