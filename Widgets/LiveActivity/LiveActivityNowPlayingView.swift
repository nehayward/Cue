#if canImport(ActivityKit)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct LiveActivityNowPlayingView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
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
        VStack(spacing: 4){
            HStack(spacing: 16) {
                Text(context.state.name)
                    .font(.headline)
                    .fontDesign(.rounded)
                Spacer()
                Link(destination: URL(string: "clic://search?id=\(context.attributes.room.id)")!) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .bold()
                }
                Button(intent: RefreshIntent()) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .bold()
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }
            VStack(alignment: .leading) {
                HStack {
                    if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .frame(width: 48, height: 48)
                    }

                    VStack(alignment: .leading) {
                        Text(context.state.trackName)
                            .bold()
                            .invalidatableContent()
                            .id(context.state.trackName)
                            .transition(updateTransition)
                        Text(context.state.artist)
                            .foregroundStyle(.secondary)
                            .invalidatableContent()
                            .id(context.state.artist)
                            .transition(updateTransition)
                    }
                    .lineLimit(0, reservesSpace: true)
                    Spacer()
                }
            }
            .frame(maxHeight: 50)
            if !isCompact {
                HStack {
                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                        Image(systemName: "minus")
                            .bold()
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.circle)
                    .tint(.primary)

                    ProgressView(value: Double(context.state.volume), total: 100)
                        .tint(.accent)
                        .invalidatableContent()
                    Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                        Image(systemName: "plus")
                            .bold()
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)
                    .buttonBorderShape(.circle)
                }
                .padding([.bottom], 4)
                HStack(spacing: 32) {
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
                .tint(.primary)
                .buttonStyle(.borderless)
            }
        }
        .font(dynamicTypeSize < .medium ? .caption : .body)
        .padding()
        .activityBackgroundTint(.clear)
        .background(.background.opacity(0.4))
        .widgetURL(URL(string: "clic://device?id=\(context.attributes.room.id)"))
    }
}

extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", ip: "1298212", name: "Gym", volume: 10))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(trackName: "Dance the Night (From The Barbie Album)",
                                                    artist: "Dua Lipa",
                                                    volume: 39,
                                                    name: "Kitchen + Gym",
                                                    TVMode: false)
    }

    fileprivate static var testing2: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(trackName: "Dance the Night",
                                                    artist: "Dua Lipa",
                                                    volume: 50,
                                                    name: "Kitchen + 1",
                                                    TVMode: false)
    }
}

#Preview("Lock Screen", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}

#Preview("Lock Screen 2", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing2
}

#Preview("Lock Screen Compact", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing2
}
#endif
