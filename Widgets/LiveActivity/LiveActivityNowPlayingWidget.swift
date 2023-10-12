import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI
import SonosKit

struct ClicNowPlayingWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var trackName: String
        var artist: String
        var volume: Double
    }
    var room: SonosDeviceEntity
}

struct LiveActivityNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClicNowPlayingWidgetAttributes.self) { context in
            LiveActivityNowPlayingView(context: context)
        } dynamicIsland: { context in
            
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hifispeaker.fill")
                }
//                DynamicIslandExpandedRegion(.trailing) {
//                    Text("\(context.state.volume, specifier: "%0.f")")
//                        .font(.caption)
//                        .contentTransition(.numericText())
//                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 12) {
                        Text(context.attributes.room.name)
                        HStack(spacing: 24) {
                            Button(intent: PlayPauseIntent(room: context.attributes.room)) {
                                Image(systemName: "playpause.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }

                            Button(intent: NextIntent(room: context.attributes.room)) {
                                Image(systemName: "forward.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                            HStack(spacing: 32) {
                                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                                    Image(systemName: "minus")
                                        .bold()
                                }
                                .buttonStyle(.borderless)
                                .buttonBorderShape(.circle)
                                .tint(.black)
                                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                                    Image(systemName: "plus")
                                        .bold()
                                }
                                .buttonStyle(.borderless)
                                .buttonBorderShape(.circle)
                                .tint(.black)
                            }
                            .padding(12)
                            .background(.secondary, in: Capsule())
                        }
                    }
                    .buttonStyle(.borderless)
                    .fontDesign(.rounded)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "speaker.wave.3.fill", variableValue: context.state.volume/100)
                            .contentTransition(.symbolEffect(.automatic))
                            .font(.caption)
                            .invalidatableContent()
                        ProgressView(value: Double(context.state.volume), total: 100)
                            .tint(.accentColor)
                            .invalidatableContent()
                        Text("\(context.state.volume, specifier: "%0.f")")
                            .font(.caption)
                            .contentTransition(.numericText())
                            .invalidatableContent()
                    }
                    .padding([.leading,.trailing])
                }
            } compactLeading: {
                Image(systemName: "hifispeaker.fill")
            } compactTrailing: {
                Text("\(context.state.volume, specifier: "%0.f")")
                    .font(.caption)
                    .contentTransition(.numericText())
            } minimal: {

            }
        }
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

#Preview("Content View", as: .dynamicIsland(.expanded), using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
