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
        var name: String
        var update: UpdateType = .refresh
    }
    var room: SonosDeviceEntity
}

struct LiveActivityNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClicNowPlayingWidgetAttributes.self) { context in
            LiveActivityNowPlayingView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Link(destination: URL(string: "clic://device?id=\(context.attributes.room.id)")!) {
                            Text(context.state.trackName)
                                .lineLimit(0)
                                .bold()
                                .invalidatableContent()
                                .id(context.state.trackName)
                                .transition(updateTransition(context: context))
                            Text(context.state.artist)
                                .lineLimit(0)
                                .invalidatableContent()
                                .id(context.state.artist)
                                .transition(updateTransition(context: context))
                        }
                        HStack {
                            Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                                Image(systemName: "minus")
                                    .bold()
                            }
                            .buttonStyle(.plain)
                            .buttonBorderShape(.circle)
                            .tint(.primary)
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
                            .contentShape(Circle())
                        }
                        .padding([.bottom], 4)
                        .frame(maxWidth: 240)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
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
                    .frame(maxWidth: .infinity)
                    .tint(.primary)
                    .buttonStyle(.borderless)
                    .overlay(alignment: .trailing) {
                        Link(destination: URL(string: "clic://search?id=\(context.attributes.room.id)")!) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .imageScale(.large)
                                .bold()
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "hifispeaker.fill")
                    .font(.caption)
            } compactTrailing: {
                Text("\(context.state.volume, specifier: "%0.f")%")
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: "hifispeaker.fill")
            }
        }
    }

    private func updateTransition(context: ActivityViewContext<ClicNowPlayingWidgetAttributes>) -> AnyTransition {
        switch context.state.update {
        case .next:
            return .push(from: .trailing)
        case .previous:
            return .push(from: .leading)
        case .refresh:
            return .opacity
        }
    }
}

extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", ip: "1298212", name: "Kitchen", volume: 10))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(trackName: "Dance the Night (From The Barbie Album)",
                                                    artist: "Dua Lipa",
                                                    volume: 39,
                                                    name: "Kitchen + 1")
     }
}

#Preview("Content View", as: .dynamicIsland(.expanded), using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
