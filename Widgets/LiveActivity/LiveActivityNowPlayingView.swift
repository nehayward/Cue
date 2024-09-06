#if canImport(ActivityKit)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

struct LiveActivityNowPlayingView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false

    private var updateTransition: AnyTransition {
        switch context.state.update {
        case .next:
            return .push(from: .trailing)
        case .previous:
            return .push(from: .leading)
        case .refresh:
            return .opacity
        }
    }

    var body: some View {
        VStack(spacing: 8) {
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
                        //                        // MARK: For Screenshots
                        //                        #if DEBUG
                        //                        .overlay {
                        //                            Rectangle()
                        //                                .foregroundStyle(.regularMaterial)
                        //                        }
                        //                        #endif
                    }
                    VStack(alignment: .leading) {
                        Text(context.state.playableContent.title)
                            .lineLimit(1)
                            .bold()
                            .invalidatableContent()
                            .id(context.state.playableContent.title)
                            .transition(updateTransition)
                        Text(context.state.playableContent.subtitle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .invalidatableContent()
                            .id(context.state.playableContent.subtitle)
                            .transition(updateTransition)
                    }
                    .lineLimit(0, reservesSpace: true)
                    Spacer()
                    if isCompact {
                        Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                            Image(systemName: "playpause.fill")
                                .frame(width: 24, height: 24)
                        }
                        .buttonBorderShape(.circle)
                        .tint(.primary)
                        Button(intent: NextIntent(room: context.attributes.room)) {
                            Image(systemName: "forward.fill")
                                .frame(width: 24, height: 24)
                        }
                        .buttonBorderShape(.circle)
                        .tint(.primary)
                    }
                }
            }
            if let settings = context.state.TVSettings {
                Text(settings.audioInputFormat.description)
                HStack(spacing: 24) {
                    Group {
                        Toggle(isOn: settings.nightMode, intent: NightModeIntent(room: context.attributes.room, nightMode: !settings.nightMode)) {
                            Label("Night Mode", systemImage: "moon.zzz.fill")
                        }
                        .labelStyle(.iconOnly)
                        .symbolRenderingMode(.hierarchical)
                        .toggleStyle(.button)
                        .frame(width: 48, height: 32)
                        .foregroundStyle(settings.nightMode ? Color.primary : .secondary.opacity(0.8))
                        .padding(.bottom, 12)

                        Toggle(isOn: settings.dialogLevel, intent: SpeechEnhancementIntent(room: context.attributes.room, speechEnhancement: !settings.dialogLevel)) {
                            Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                        }
                        .symbolRenderingMode(.hierarchical)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .foregroundStyle(settings.dialogLevel ? Color.primary : .secondary.opacity(0.8))
                        .frame(width: 48, height: 32)
                        .padding(.bottom, 12)
                    }
                    .tint(.teal)
                }
            } else {
                if !isCompact {
                    HStack(spacing: 24) {
                        Group {
                            Button(intent: PreviousIntent(room: context.attributes.room)) {
                                Image(systemName: "backward.fill")
                                    .frame(width: 24, height: 24)
                            }
                            Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                                Image(systemName: "playpause.fill")
                                    .frame(width: 32, height: 32)
                            }
                            Button(intent: NextIntent(room: context.attributes.room)) {
                                Image(systemName: "forward.fill")
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .tint(.primary)
                        .buttonStyle(.liveActivity)
                    }
                    .frame(maxHeight: 20)
                }
            }
            if !isCompact {
                HStack {
                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                        Image(systemName: "minus")
                            .bold()
                            .frame(width: 24, height: 24)
                    }
                    .tint(.primary)
                    .buttonStyle(.liveActivity)

                    VibeSlider(value: .constant(Double(context.state.volume)), baseHeight: 12)
                        .foregroundStyle(.teal)
                        .invalidatableContent()
                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                            .bold()
                    }
                    .tint(.primary)
                    .buttonStyle(.liveActivity)
                }
                .padding([.bottom], 8)
                .frame(maxHeight: 24)
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
