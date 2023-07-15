import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI
import SonosKit

struct SonosWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var date: Date
    var name: String
    var speaker: String
    var ip: String
    var isPlaying: Bool
    var sonosSpeaker: SonosSpeakerEntity
    var volume: Double
}

struct SonosWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SonosWidgetAttributes.self) { context in
            VStack(spacing: 0) {
                Text(context.state.emoji)
                Label(context.attributes.name, systemImage: "hifispeaker.fill")
                    .padding(.bottom, 12)
                HStack(spacing: 24) {
                    Button(intent: PlayIntent(speaker: context.attributes.sonosSpeaker)) {
                        Image(systemName: "playpause.circle.fill")
                            .resizable()
                            .tint(.secondary)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    }

                    Button(intent: NextIntent(speaker: context.attributes.sonosSpeaker)) {
                        Image(systemName: "forward.circle.fill")
                            .resizable()
                            .tint(.secondary)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.bottom, 12)
                HStack(spacing: 24) {
                    Button(intent: SetVolumeIntent(speaker: context.attributes.sonosSpeaker, volume: -5)) {
                        Image(systemName: "minus.circle.fill")
                            .resizable()
                            .tint(.secondary)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    }
                    Button(intent: SetVolumeIntent(speaker: context.attributes.sonosSpeaker, volume: 5)) {
                        Image(systemName: "plus.circle.fill")
                            .resizable()
                            .tint(.secondary)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.bottom, 12)
                ProgressView(value: Double(context.attributes.volume), total: 100)
            }
            .buttonStyle(.borderless)
            .fontDesign(.rounded)
//            .containerBackground(.thickMaterial, for: .widget)
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        Text(context.state.emoji)
                        Label(context.attributes.name, systemImage: "hifispeaker.fill")
                            .padding(.bottom, 12)
                        HStack(spacing: 24) {
                            Button(intent: PlayIntent(speaker: context.attributes.sonosSpeaker)) {
                                Image(systemName: "playpause.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }

                            Button(intent: NextIntent(speaker: context.attributes.sonosSpeaker)) {
                                Image(systemName: "forward.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.bottom, 12)
                        HStack(spacing: 24) {
                            Button(intent: SetVolumeIntent(speaker: context.attributes.sonosSpeaker, volume: -5)) {
                                Image(systemName: "minus.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                            Button(intent: SetVolumeIntent(speaker: context.attributes.sonosSpeaker, volume: 5)) {
                                Image(systemName: "plus.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.bottom, 12)
                        ProgressView(value: Double(context.attributes.volume), total: 100)
                    }
                    .buttonStyle(.borderless)
                    .fontDesign(.rounded)
        //            .containerBackground(.thickMaterial, for: .widget)
                    .activityBackgroundTint(Color.cyan)
                    .activitySystemActionForegroundColor(Color.black)
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
        }
    }
}

extension SonosWidgetAttributes {
    fileprivate static var preview: SonosWidgetAttributes {
        SonosWidgetAttributes(date: .now, name: "Garage", speaker: "192.168.4.50", ip: "", isPlaying: false,  sonosSpeaker: SonosSpeakerEntity(id: "", name: "Garage", ip: "192.168.4.50", volume: 0), volume: 0)
    }
}

extension SonosWidgetAttributes.ContentState {
    fileprivate static var smiley: SonosWidgetAttributes.ContentState {
        SonosWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SonosWidgetAttributes.ContentState {
         SonosWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .dynamicIsland(.expanded), using: SonosWidgetAttributes.preview) {
    SonosWidgetLiveActivity()
} contentStates: {
    SonosWidgetAttributes.ContentState.smiley
}
