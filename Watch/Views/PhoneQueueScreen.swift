import SwiftUI
import WatchSync

/// Up Next for what the iPhone plays (`PhoneNowPlaying.queue`), opened from
/// the top right of its player: the song playing and the ones after it,
/// here or on the iPhone's Sonos group, as the iPhone's own Up Next lists
/// them. A tap plays that song there and goes back to the player. While the
/// queue waits behind what plays (a station, a speaker on radio or TV) it
/// says so, dimmed, with no song playing, and a tap goes back to it. Asked
/// for as it opens and again whenever the iPhone says the queue moved.
struct PhoneQueueScreen: View {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(\.dismiss) private var dismiss

    /// What says the queue moved: the place in it, or its length.
    private var stamp: [Int] {
        [phone.current?.queuePosition ?? 0, phone.current?.queueCount ?? 0]
    }

    var body: some View {
        Group {
            if phone.current == nil {
                Text(phone.isPhoneInReach ? "Nothing playing on iPhone" : "iPhone out of reach")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let queue = phone.queue {
                if queue.songs.isEmpty {
                    Text("Nothing queued")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    list(queue)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Up Next")
        .containerBackground(for: .navigation) {
            ImageMeshFill(image: phone.artwork)
        }
        .task(id: stamp) {
            phone.refreshQueue()
        }
    }

    private func list(_ queue: WatchPhoneQueue) -> some View {
        List {
            Section {
                ForEach(queue.songs) { song in
                    Button {
                        phone.playFromQueue(at: song.position)
                        dismiss()
                    } label: {
                        PhoneQueueRow(
                            song: song,
                            isCurrent: song.position == queue.current,
                            isPlaying: phone.current?.isPlaying == true
                        )
                    }
                    .opacity(queue.isWaiting ? 0.6 : 1)
                }
            } header: {
                if queue.isWaiting {
                    Text("Not Active")
                }
            } footer: {
                if queue.remaining > 0 {
                    Text(queue.remaining == 1 ? "1 more song" : "\(queue.remaining) more songs")
                }
            }
        }
    }
}

/// A song in the iPhone's queue: the one playing in the tint, with a
/// waveform that moves while it plays.
private struct PhoneQueueRow: View {
    let song: WatchPhoneQueue.Song
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading) {
                Text(song.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                if let artist = song.artist {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .accessibilityLabel(isPlaying ? "Playing" : "Paused")
            }
        }
    }
}
