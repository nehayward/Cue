#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI
import SonosKit
import VibesDS

struct ClicNowPlayingWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var playableContent: PlayableContent
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
            LiveActivityNowPlaying(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) var isCompact: Bool = false

                    VStack {
                        Link(destination: URL(string: "clic://device?id=\(context.attributes.room.id)")!) {
                            HStack {
                                if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .frame(width: 48, height: 48)
                                        .overlay(alignment: .bottomTrailing) {
                                            context.state.playableContent.content.service.icon
                                                .frame(width: 8, height: 8, alignment: .bottomLeading)
                                                .padding([.bottom, .trailing], 2)
                                        }
                                }
                                VStack(alignment: .leading) {
                                    Text(context.state.playableContent.title)
                                        .lineLimit(0)
                                        .bold()
                                        .invalidatableContent()
                                        .id(context.state.playableContent.title)
                                        .transition(updateTransition(context: context))
                                    Text(context.state.playableContent.subtitle)
                                        .lineLimit(0)
                                        .foregroundStyle(.secondary)
                                        .invalidatableContent()
                                        .id(context.state.playableContent.subtitle)
                                        .transition(updateTransition(context: context))
                                }
                                if let settings = context.state.TVSettings {
                                    Text(settings.audioInputFormat.description)
                                } else {
                                    Spacer()
                                }
                            }
                        }
                        if !isCompact {
                            HStack {
                                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                                    Image(systemName: "minus")
                                        .bold()
                                }
                                .tint(.primary)
                                .buttonStyle(.liveActivity)
                                VibeSlider(value: .constant(Double(context.state.volume)), baseHeight: 12)
                                    .foregroundStyle(.teal)
                                    .invalidatableContent()
                                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                                    Image(systemName: "plus")
                                        .bold()
                                }
                                .tint(.primary)
                                .buttonStyle(.liveActivity)
                            }
                            .frame(maxWidth: 240)
                            .frame(height: 12)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        if let settings = context.state.TVSettings {
                            Toggle(isOn: settings.nightMode, intent: NightModeIntent(room: context.attributes.room, nightMode: !settings.nightMode)) {
                                Label("Night Mode", systemImage: "moon.zzz.fill")
                            }
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(settings.nightMode ? Color.teal : .secondary.opacity(0.8))
                            .frame(width: 32, height: 32)

                            Toggle(isOn: settings.dialogLevel, intent: SpeechEnhancementIntent(room: context.attributes.room, speechEnhancement: !settings.dialogLevel)) {
                                Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                            }
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(settings.dialogLevel ? Color.teal : .secondary.opacity(0.8))
                            .frame(width: 32, height: 32)
                        } else {
                            Button(intent: PreviousIntent(room: context.attributes.room)) {
                                Image(systemName: "backward.fill")
                            }
                            Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                                Image(systemName: "playpause.fill")
                                    .imageScale(.large)
                            }
                            Button(intent: NextIntent(room: context.attributes.room)) {
                                Image(systemName: "forward.fill")
                                    .frame(width: 24, height: 24)
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
                    .overlay(alignment: .leading) {
                        Link(destination: URL(string: "clic://group?id=\(context.attributes.room.id)")!) {
                            Image("hifispeaker.circle.fill")
                                .imageScale(.large)
                                .bold()
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                if context.state.TVSettings != nil {
                    Image(systemName: "tv.and.hifispeaker.fill")
                } else {
                    Image(systemName: "hifispeaker.fill")
                        .symbolRenderingMode(.hierarchical)
                        .fontDesign(.rounded)
                }
            } compactTrailing: {
                if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(width: 20, height: 20)
                        .overlay(alignment: .bottomTrailing) {
                            context.state.playableContent.content.service.icon
                                .frame(width: 8, height: 8, alignment: .bottomLeading)
                                .padding([.bottom, .trailing], 1)

                        }
                }
            } minimal: {
                Image(systemName: "hifispeaker.fill")
            }
        }
//        .supplementalActivityFamiliesBackDeployment()
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

extension WidgetConfiguration {
    func supplementalActivityFamiliesBackDeployment() -> some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return self.supplementalActivityFamilies([.small])
        } else {
            return self
        }
    }
}


extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", ip: "1298212", name: "Kitchen"))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa",  thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)),
            volume: 39,
            name: "Kitchen + 1",
            TVMode: false
        )
     }

    
}

#Preview("Content View", as: .dynamicIsland(.expanded), using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
#endif
