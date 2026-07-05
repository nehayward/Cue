import SwiftUI
import SonosKit
import WidgetKit
import VibesDS

struct RemoteWidgetLargeView: View {
    var entry: Provider.Entry

    var body: some View {
        if let room = entry.configuration.room {
            VStack(spacing: 4) {
                HStack(spacing: 16) {
                    Text(entry.name ?? room.name)
                        .font(.headline)
                        .fontDesign(.rounded)
                        .opacity(0.8)
                        .lineLimit(1)
                    Spacer()
                    if entry.activeSubscription {
                        Link(destination: URL(string: "clic://group?id=\(room.id)")!) {
                            Image("hifispeaker.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .bold()
                        }
                    } else {
                        Image("hifispeaker.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .bold()
                            .opacity(0.5)
                    }
                    if entry.activeSubscription {
                        Link(destination: URL(string: "clic://search?id=\(room.id)")!) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .bold()
                        }
                    } else {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .bold()
                            .opacity(0.5)
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
                
                if let theater = entry.TVSettings {
                    Spacer()
                    Text(theater.audioInputFormat.description)
                    HStack(spacing: 12) {
                        Toggle(isOn: theater.nightMode, intent: SetNightModeIntent(room: room, nightMode: !theater.nightMode)) {
                            Label("Night Mode", systemImage: "moon.zzz.fill")
                                .foregroundStyle(.accent)
                                .widgetAccentable()
                        }
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .frame(width: 40, height: 40) // Makes it a perfect circle
                        .buttonStyle(.plain)
                        .background(
                            Circle()
                                .fill(.fill)
                        )
                        .opacity(theater.nightMode ? 1 : 0.4)
                        .invalidatableContent()
                        
                        Toggle(isOn: entry.isMuted, intent: MuteIntent(room: room, mute: .toggle)) {
                            Image(systemName: entry.isMuted ? "speaker.slash.fill" : "speaker.fill")
                                .frame(width: 24, height: 24)
                        }
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .frame(width: 40, height: 40) // Makes it a perfect circle
                        .buttonStyle(.plain)
                        .background(
                            Circle()
                                .fill(.fill)
                        )
                        .invalidatableContent()

                        Toggle(isOn: theater.speechIsActive, intent: SetSpeechEnhancementIntent(room: room, speechEnhancement: !theater.speechIsActive)) {
                            Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                                .foregroundStyle(.accent)
                                .widgetAccentable()
                        }
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .frame(width: 40, height: 40) // Makes it a perfect circle
                        .buttonStyle(.plain)
                        .background(
                            Circle()
                                .fill(.fill)
                        )
                        .opacity(theater.speechIsActive ? 1 : 0.4)
                        .invalidatableContent()
                    }
                    VibeNumberSlider(value: .constant(Double(entry.volume))) { number in
                        Button(intent: SetVolumeIntent(room: room, volume: Double(number))) {
                            
                        }
                    }
                    .padding([.leading, .trailing])
                } else {
                    HStack {
                        Group {
                            if let image = ArtworkManager.shared.getImage(name: entry.name ?? room.name) {
                                Image(uiImage: image)
                                    .resizable()
                                    .backdeployedWidgetAccentedRenderingMode(.fullColor)
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .frame(width: 80, height: 80)
                                    .overlay(alignment: .bottomTrailing) {
                                        entry.playableContent?.content.service.icon
                                            .frame(width: 16, height: 16, alignment: .bottomLeading)
                                            .padding([.bottom, .trailing], 4)
                                    }
                                //                        // MARK: For Screenshots
                                //                        #if DEBUG
                                //                        .overlay {
                                //                            Rectangle()
                                //                                .foregroundStyle(.regularMaterial)
                                //                        }
                                //                        #endif
                            } else  {
                                Rectangle()
                                    .foregroundStyle(.thickMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .frame(width: 80, height: 80)
                            }
                        }.overlay {
                            if entry.isMuted {
                                RoundedRectangle(cornerRadius: 4)
                                    .foregroundStyle(.ultraThinMaterial)
                                    .overlay {
                                        Image(systemName: "speaker.slash.fill")
                                    }
                            }
                        }
                        VStack(alignment: .leading) {
                            Text(entry.playableContent?.title ?? "")
                                .lineLimit(1)
                                .bold()
                                .invalidatableContent()
                                .id(entry.playableContent?.title)
                            Text(entry.playableContent?.subtitle ?? "")
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                                .invalidatableContent()
                                .id(entry.playableContent?.subtitle)
                            HStack(spacing: 24) {
                                Group {
                                    Button(intent: PreviousIntent(room: room)) {
                                        Image(systemName: "backward.fill")
                                            .frame(width: 24, height: 24)
                                    }
                                    Button(intent: TogglePlaybackIntent(room: room)) {
                                        Image(systemName: "playpause.fill")
                                            .frame(width: 32, height: 32)
                                    }
                                    Button(intent: NextIntent(room: room)) {
                                        Image(systemName: "forward.fill")
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .tint(.primary)
                                .buttonStyle(.liveActivity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 24, alignment: .center)
                        }
                        .lineLimit(0, reservesSpace: true)
                    }
                    VibeNumberSlider(value: .constant(Double(entry.volume))) { number in
                        Button(intent: SetVolumeIntent(room: room, volume: Double(number))) {
                            
                        }
                    }
                    ForEach(entry.playHistory.prefix(UIDevice.current.userInterfaceIdiom == .pad ? 3 : 4)) { playHistory in
                        HStack {
                            Image(systemName: playHistory.content.type.symbol)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(playHistory.title)
                                Text(playHistory.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            Spacer()
                            Button(intent: PlayIntent(room: room, title: playHistory.title, id: playHistory.content.id, service: playHistory.content.service.sonosRawValue, type: playHistory.content.type.sonosRawValue)) {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.accent)
                                    .widgetAccentable()
                            }
                        }
                    }
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .containerBackground(.widgetBackground, for: .widget)
            .fontDesign(.rounded)
            .widgetURL(entry.activeSubscription ? URL(string: "clic://device?id=\(room.id)") : nil)
        } else {
            Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }
    }
}

#Preview("Active Subscription", as: .systemLarge) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.largePreview()
    RemoteWidgetEntry.previewBarbie()
    RemoteWidgetEntry.previewBarbie(service: .spotify)
    RemoteWidgetEntry.previewBarbie(service: .tidal)
    RemoteWidgetEntry.previewBarbie(service: .unknown)
    RemoteWidgetEntry.previewBarbie(false, service: .apple)
    RemoteWidgetEntry.previewTheater(service: .apple)
}

#Preview("No Subscription", as: .systemLarge) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie(false)
}
