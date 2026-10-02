import SwiftUI
import WatchSync

/// An album, playlist, artist or the Songs list on the watch: Play and
/// Shuffle for what's here, and each song with where its download stands.
struct CollectionScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    let collectionKey: String

    var body: some View {
        if let collection = store.library.collection(key: collectionKey) {
            let tracks = store.library.tracks(in: collection)
            let downloaded = tracks.filter { store.isPlayable($0.key) }
            List {
                Section {
                    VStack(spacing: 4) {
                        ArtworkView(url: collection.artworkURL)
                            .frame(width: 80, height: 80)
                        Text(collection.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        if !collection.subtitle.isEmpty {
                            Text(collection.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                    HStack {
                        Button {
                            player.play(downloaded)
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Play")
                        Button {
                            player.play(downloaded, shuffled: true)
                        } label: {
                            Image(systemName: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Shuffle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(downloaded.isEmpty)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(tracks) { track in
                        Button {
                            player.play(downloaded, startingAt: track.key)
                        } label: {
                            TrackRow(track: track, item: store.item(for: track.key), isCurrent: player.current?.key == track.key)
                        }
                        .disabled(!store.isPlayable(track.key))
                    }
                } footer: {
                    if downloaded.count < tracks.count {
                        Text("\(downloaded.count) of \(tracks.count) songs on this watch. Fast Download fetches the rest over Wi‑Fi.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.removeCollection(key: collection.key)
                        dismiss()
                    } label: {
                        Text("Remove from Watch")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(collection.title)
        } else {
            Text("Removed from this watch")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrackRow: View {
    let track: WatchTrack
    let item: WatchDownloadStore.Item?
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading) {
                Text(track.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(track.artist)
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
            EmptyView()
        case .downloading:
            // A transcoded stream doesn't say how big it is, so there's no
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
