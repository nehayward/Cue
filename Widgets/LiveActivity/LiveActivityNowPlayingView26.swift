#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

struct LiveActivityNowPlayingView26: View {
    let context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false
    @AppStorage("LiveActivityStep", store: UserDefaults(suiteName: "group.com.clic")) private var liveActivityStep: Int = 5

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Text(context.state.name)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .opacity(0.8)
                Spacer()
                Link(destination: URL(string: "clic://group?id=\(context.attributes.room.id)")!) {
                    Image("hifispeaker.circle.fill")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .bold()
                }
                Link(destination: URL(string: "clic://search?id=\(context.attributes.room.id)")!) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .bold()
                }
                Button(intent: RefreshIntent()) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .bold()
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }
            if context.state.TVSettings == nil {
                HStack {
                    Group {
                        if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 48, height: 48)
                                .overlay(alignment: .bottomTrailing) {
                                    context.state.playableContent.content.service.icon
                                        .frame(width: 8, height: 8, alignment: .bottomLeading)
                                        .padding([.bottom, .trailing], 4)
                                }
                                .animation(.spring, value: context.state)
#if DEBUG && SCREENSHOT
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.ultraThinMaterial)
                                }
#endif
                            //                        // MARK: For Screenshots
                            //                        #if DEBUG
                            //                        .overlay {
                            //                            Rectangle()
                            //                                .foregroundStyle(.regularMaterial)
                            //                        }
                            //                        #endif
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .frame(width: 48, height: 48)
                        }
                    }.overlay {
                        if context.state.isMuted {
                            RoundedRectangle(cornerRadius: 4)
                                .foregroundStyle(.ultraThinMaterial)
                                .overlay {
                                    Image(systemName: "speaker.slash.fill")
                                }
                        }
                    }
                    VStack(alignment: .leading) {
                        Text(context.state.playableContent.title)
                            .lineLimit(1)
                            .bold()
                            .animation(.spring, value: context.state)
                        Text(context.state.playableContent.subtitle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .animation(.spring, value: context.state)
                    }
                    .lineLimit(0, reservesSpace: true)
                    .invalidatableContent()
                    Spacer()
                    HStack(spacing: 0) {
                        Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                            Image(systemName: "playpause.fill")
                                .frame(width: 24, height: 24)
                        }
                        .tint(.primary)
                        .buttonStyle(.liveActivity)
                        
                        Button(intent: NextIntent(room: context.attributes.room)) {
                            Image(systemName: "forward.fill")
                                .frame(width: 24, height: 24)
                        }
                        .tint(.primary)
                        .buttonStyle(.liveActivity)
                    }
                }
            }
            if let settings = context.state.TVSettings {
                Text(settings.audioInputFormat.description)
                HStack(spacing: 24) {
                    Toggle(isOn: settings.nightMode, intent: SetNightModeIntent(room: context.attributes.room, nightMode: !settings.nightMode)) {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                    }
                    .labelStyle(.iconOnly)
                    .symbolRenderingMode(.hierarchical)
                    .toggleStyle(.button)
                    .frame(width: 32, height: 28)
                    .foregroundStyle(settings.nightMode ? Color.primary : .secondary.opacity(0.8))
                    
//                    Toggle(isOn: context.state.isMuted, intent: MuteIntent(room: context.attributes.room, mute: .toggle)) {
//                        Label("", systemImage: context.state.isMuted ? "speaker.slash.fill" : "speaker.fill")
//                    }
//                    .tint(context.state.isMuted ? .accent : .primary)
//                    .labelStyle(.iconOnly)
//                    .symbolRenderingMode(.hierarchical)
//                    .toggleStyle(.button)
//                    .frame(width: 32, height: 28)
//                    .foregroundStyle(context.state.isMuted ? Color.primary : .secondary.opacity(0.8))
                    
                    Toggle(isOn: settings.dialogLevel, intent: SetSpeechEnhancementIntent(room: context.attributes.room, speechEnhancement: !settings.dialogLevel)) {
                        Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                    }
                    .symbolRenderingMode(.hierarchical)
                    .labelStyle(.iconOnly)
                    .toggleStyle(.button)
                    .foregroundStyle(settings.dialogLevel ? Color.primary : .secondary.opacity(0.8))
                    .frame(width: 32, height: 28)
                }
                .tint(.black)
            }
            if !isCompact {
                HStack {
//                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
//                        Image(systemName: "minus")
//                            .bold()
//                            .frame(width: 24, height: 24)
//                    }
//                    .tint(.primary)
//                    .buttonBorderShape(.circle)
//                    .buttonStyle(.liveActivity)

                    VibeNumberSlider(value: .constant(Double(context.state.volume)), visibleCount: 3, step: Double(liveActivityStep)) { number in
                        Button(intent: SetVolumeIntent(room: context.attributes.room, volume: Double(number))) {
                            
                        }
                    }
                    
//                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
//                        Image(systemName: "plus")
//                            .frame(width: 24, height: 24)
//                            .bold()
//                    }
//                    .tint(.primary)
//                    .buttonBorderShape(.circle)
//                    .buttonStyle(.liveActivity)
                }
//                .padding([.bottom], 8)
//                .frame(height: 48)
            }
        }
        .font(dynamicTypeSize < .medium ? .caption : .body)
        .padding()
        .activityBackgroundTint(.clear)
        .background(.background.opacity(0.4))
        .widgetURL(URL(string: "clic://device?id=\(context.attributes.room.id)"))
    }
}
#endif
