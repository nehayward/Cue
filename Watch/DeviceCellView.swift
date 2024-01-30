import Nuke
import NukeUI
import SwiftUI
import SonosKit

struct DeviceCellView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Binding var group: GroupRoom
    @State private var artworkURL: URL?

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    if let settings = group.tvSettings {
                        Text(settings.audioInputFormat.description)
                    } else {
                        HStack {
                            LazyImage(url: artworkURL) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if state.isLoading {
                                    RoundedRectangle(cornerRadius: 4)
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.ultraThinMaterial)
                                        .shadow(radius: 2)
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.accent.gradient.secondary)
                                        .shadow(radius: 2)
                                        .overlay {
                                            if artworkURL == nil {
                                                Image(systemName: "music.note")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .foregroundStyle(.regularMaterial)
                                                    .frame(width: 24, height: 24)
                                            }
                                        }
                                }
                            }
                            .transition(.scale)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(radius: 2)
                            .frame(width: 40, height: 40)
                            .overlay(alignment: .bottomTrailing) {
                                switch group.coordinatorRoom.track.musicService {
                                case .apple:
                                    Image(systemName: "apple.logo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 10, height: 10)
                                        .padding([.trailing, .bottom], 4)
                                        .shadow(radius: 10)
                                case .spotify:
                                    Image(.spotifyLogo)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 10, height: 10)
                                        .padding([.trailing, .bottom], 4)
                                        .shadow(radius: 10)
                                case .airplay, .unknown:
                                    EmptyView()
                                        .padding([.trailing, .bottom], 12)
                                }
                            }
                            VStack(alignment: .leading) {
                                Text(group.coordinatorRoom.track.name)
                                    .lineLimit(1, reservesSpace: true)
                                    .redacted(reason: group.coordinatorRoom.track.name.isEmpty ? .placeholder : [])
                                Text(group.coordinatorRoom.track.artist)
                                    .lineLimit(1, reservesSpace: true)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer()
                if group.tvSettings == nil && group.coordinatorRoom.track != .empty {
                    Button {
                        Task {
                            if group.coordinatorRoom.isPlaying {
                                WKInterfaceDevice.current().play(.stop)
                                await sonosService.pause(ip: group.coordinatorRoom.ip)
                            } else {
                                WKInterfaceDevice.current().play(.start)
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        }
                    } label: {
                        Gauge(
                            value: group.coordinatorRoom.track.playbackPosition,
                            in: 0...group.coordinatorRoom.track.duration,
                            label: {

                            },
                            currentValueLabel: {
                                Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                                    .renderingMode(.template)
                                    .foregroundColor(.accentColor)
                                    .contentTransition(.symbolEffect(.automatic))
                            }
                        )
                        .tint(group.coordinatorRoom.isPlaying ? .accentColor : Color.secondary)
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.65)
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
           Text(group.nameWithCount)
        }
        .tag(group.coordinatorID)
        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
        .task(id: group.coordinatorRoom.track.id) {
            artworkURL = await sonosService.getArtwork(from: group.coordinatorRoom.track, size: 200)
        }
    }
}


#Preview {
    DeviceCellView(group: .constant(.theater))
        .environment(SonosService())
}
