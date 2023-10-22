import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct LiveActivityNowPlayingView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(context.attributes.room.name, systemImage: "hifispeaker.fill")
                    Text(context.state.trackName)
                        .lineLimit(0)
                        .bold()
                    Text(context.state.artist)
                        .lineLimit(0)
                    HStack(spacing: 6) {
                        Spacer()
                        Button(intent: PreviousIntent(room: context.attributes.room)) {
                            Image(systemName: "backward.fill")
                        }

                        Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                            Image(systemName: "playpause.fill")
                                .imageScale(.large)
                        }

                        Button(intent: NextIntent(room: context.attributes.room)) {
                            Image(systemName: "forward.fill")
                        }
                        Spacer()
                    }
                    .tint(.primary)
                    .frame(alignment: .center)
                    .padding([.horizontal])
                }
                VStack(spacing: 6) {
                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                        Image(systemName: "plus")
                            .bold()
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)
                    .buttonBorderShape(.circle)
                    .frame(width: 42, height: 42)

                    Spacer()
                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                        Image(systemName: "minus")
                            .bold()
                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.circle)
                    .tint(.primary)
                    .frame(width: 42, height: 42)
                }
                .background(.secondary, in: Capsule())
            }
            HStack {
                Image(systemName: "speaker.wave.3.fill", variableValue: context.state.volume/100)
                    .contentTransition(.symbolEffect(.automatic))
                    .font(.caption)
                ProgressView(value: Double(context.state.volume), total: 100)
                    .tint(.accentColor)
                Text("\(context.state.volume, specifier: "%0.f")")
                    .font(.caption)
                    .contentTransition(.numericText())
            }
            .padding([.bottom])
            .invalidatableContent()
        }
        .padding([.horizontal, .top])
    }
}

extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", name: "Kitchen", ip: "1298212", volume: 10))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(trackName: "Dance the Night (From The Barbie Album)",
                                                    artist: "Dua Lipa",
                                                    volume: 39)
    }
}

#Preview("Content View", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
