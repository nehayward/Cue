import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct LiveActivityNowPlayingView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>

    var body: some View {
        VStack {
            HStack {
                Label(context.attributes.room.name,
                      systemImage: "hifispeaker.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Search")
                Text("Refresh")
            }
            Text(context.state.trackName)
                .lineLimit(0)
                .bold()
            Text(context.state.artist)
                .lineLimit(0)
            HStack {
                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                    Image(systemName: "minus")
                        .bold()
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .tint(.primary)
//                .frame(width: 42, height: 42)

                ProgressView(value: Double(context.state.volume), total: 100)
                    .tint(.teal)
                    .invalidatableContent()
                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                    Image(systemName: "plus")
                        .bold()
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .buttonBorderShape(.circle)
//                .frame(width: 42, height: 42)

            }
            .padding([.bottom])
            .invalidatableContent()
            HStack(spacing: 16) {
                Button(intent: PreviousIntent(room: context.attributes.room)) {
                    Image(systemName: "backward.end.fill")
                }
                Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                    Image(systemName: "playpause.fill")
                        .imageScale(.large)
                }
                Button(intent: NextIntent(room: context.attributes.room)) {
                    Image(systemName: "forward.end.fill")
                }
            }
            .tint(.primary)
            .buttonStyle(.borderless)
        }
        .padding()
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
