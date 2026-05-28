import SwiftUI
import Kingfisher

struct MediaIndicatorView: View {
    let speakerName: String
    let action: MediaAction
    var onDismiss: (() -> Void)? = nil

    enum MediaAction {
        case volumeUp(volume: Double)
        case volumeDown(volume: Double)
        case mute(volume: Double)
        /// A track being shown. `direction` is set only for a user-initiated skip
        /// (key command) — that's when the skip badge shows. A natural track
        /// change passes `nil` so no badge appears. `loading == true` keeps the
        /// current artwork up while the new track resolves.
        case track(direction: Direction?, title: String, artist: String, albumName: String, imageURL: URL?, loading: Bool)

        enum Direction { case next, previous }

        var title: String {
            switch self {
            case .volumeUp, .volumeDown, .mute: return "Volume"
            case .track(let direction, _, _, _, _, _):
                switch direction {
                case .next: return "Next Track"
                case .previous: return "Previous Track"
                case nil: return "Now Playing"
                }
            }
        }

        var hasVolumeInfo: Bool {
            switch self {
            case .volumeUp, .volumeDown, .mute: return true
            case .track: return false
            }
        }

        var volume: Double? {
            switch self {
            case .volumeUp(let vol), .volumeDown(let vol), .mute(let vol): return vol
            case .track: return nil
            }
        }
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss?() }
    }

    @ViewBuilder
    private var content: some View {
        if action.hasVolumeInfo, let volume = action.volume {
            volumeContent(volume)
        } else if case let .track(direction, title, artist, albumName, imageURL, loading) = action {
            trackContent(direction: direction, title: title, artist: artist, albumName: albumName, imageURL: imageURL, loading: loading)
        }
    }

    private func volumeContent(_ volume: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(speakerName)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(action.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(volume))")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            VibeMiniSlider(value: .constant(volume), baseHeight: 12)
                .frame(height: 12)
        }
    }

    private func trackContent(direction: MediaAction.Direction?, title: String, artist: String, albumName: String, imageURL: URL?, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(speakerName)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                ZStack {
                    KFImage.url(imageURL, cacheKey: albumName)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 6)
                                .foregroundStyle(.thinMaterial)
                        }
                        .diskCacheExpiration(.days(1))
                        .fade(duration: 0.2)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(loading ? 0.6 : 1)

                    if let direction {
                        // User-initiated skip: centered badge that pops then fades.
                        // Keyed on title so it re-fires per skip; a rapid
                        // loading→resolved just keeps it up and fades once.
                        SkipBadge(forward: direction == .next)
                            .id(title)
                    } else if loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if !artist.isEmpty {
                        Text(artist)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A small forward/back glyph that pops on the artwork corner and fades away
/// shortly after a skip, then stays gone.
private struct SkipBadge: View {
    let forward: Bool
    @State private var visible = false

    var body: some View {
        Image(systemName: forward ? "forward.fill" : "backward.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.5), in: Circle())
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.5)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    visible = true
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.6)) {
                    visible = false
                }
            }
    }
}

#Preview {
    MediaIndicatorView(speakerName: "Kitchen", action: .volumeUp(volume: 42))
    MediaIndicatorView(speakerName: "Kitchen", action: .track(direction: .next, title: "Get Lucky (feat. Pharrell Williams)", artist: "Daft Punk", albumName: "", imageURL: URL(string: "https://upload.wikimedia.org/wikipedia/en/c/c7/Dua_Lipa_-_Dance_the_Night.png"), loading: false))
    MediaIndicatorView(speakerName: "Kitchen", action: .track(direction: .previous, title: "Get Lucky", artist: "Daft Punk", albumName: "", imageURL: nil, loading: true))
}
