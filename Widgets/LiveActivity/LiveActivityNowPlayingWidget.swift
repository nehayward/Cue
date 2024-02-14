#if canImport(ActivityKit)
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
        var TVMode: Bool
        var TVSettings: TVSettings? = nil
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
                            HStack {
                                if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .frame(width: 50, height: 50)
                                }
                                VStack(alignment: .leading) {
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
                                if context.state.TVSettings != nil || context.state.trackName == "Nothing playing" {

                                } else {
                                    Spacer()
                                }
                            }
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
                        if let settings = context.state.TVSettings {
                            Toggle(isOn: settings.nightMode, intent: NightModeIntent(room: context.attributes.room, nightMode: !settings.nightMode)) {
                                Label("Night Mode", systemImage: "moon.zzz")
                            }
                            .symbolVariant(settings.nightMode ? .fill : .none)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .buttonBorderShape(.circle)
                            .foregroundStyle(.thickMaterial)
                            .frame(width: 40, height: 40)
                            .tint(.secondary)
                            .background(settings.nightMode ? .primary : .tertiary, in: Capsule())
                            
                            Toggle(isOn: settings.dialogLevel, intent: SpeechEnhancementIntent(room: context.attributes.room, speechEnhancement: !settings.dialogLevel)) {
                                Label("Speech Enhancement", systemImage: "person.wave.2")
                            }
                            .symbolVariant(settings.dialogLevel ? .fill : .none)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .buttonBorderShape(.circle)
                            .foregroundStyle(.thickMaterial)
                            .frame(width: 40, height: 40)
                            .tint(.secondary)
                            .background(settings.dialogLevel ? .primary : .tertiary, in: Capsule())
                        } else {
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
                if context.state.TVSettings != nil {
                    Image(systemName: "tv.and.hifispeaker.fill")
                } else {
                    Image(systemName: "hifispeaker.fill")
                }
            } compactTrailing: {
                if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(width: 20, height: 20)
                }
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
                                                    name: "Kitchen + 1",
                                                    TVMode: false)
     }
}

#Preview("Content View", as: .dynamicIsland(.expanded), using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
#endif
