import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetMediumView: View {
    var entry: Provider.Entry
    @Environment(\.widgetRenderingMode) var widgetRenderingMode

    var body: some View {
        if let room = entry.configuration.room {
            VStack {
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

                        Toggle(isOn: theater.dialogLevel, intent: SetSpeechEnhancementIntent(room: room, speechEnhancement: !theater.dialogLevel)) {
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
                        .opacity(theater.dialogLevel ? 1 : 0.4)
                        .invalidatableContent()
                    }
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
                        }
                        .lineLimit(0, reservesSpace: true)
                        Spacer()
                    }
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .containerBackground(for: .widget) {
                if entry.configuration.plainBackground {
                    Rectangle().foregroundStyle(.widgetBackground)
                } else {
                    if let image = ArtworkManager.shared.getImage(name: entry.name ?? room.name) {
                        Image(uiImage: image)
                            .resizable()
                            .backdeployedWidgetAccentedRenderingMode(.fullColor)
                            .blur(radius: 20)
                            .ignoresSafeArea()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay {
                                Rectangle()
                                    .foregroundStyle(.ultraThinMaterial)
                            }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if entry.TVSettings == nil {
                    HStack {
                        Group {
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
                    .frame(maxHeight: 24)
                }
            }
            .fontDesign(.rounded)
            .widgetURL(entry.activeSubscription ? URL(string: "clic://device?id=\(room.id)") : nil)
        } else {
            Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }
    }
}

#Preview("Active Subscription", as: .systemMedium) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
    RemoteWidgetEntry.previewBarbie(service: .spotify)
    RemoteWidgetEntry.previewBarbie(service: .tidal)
    RemoteWidgetEntry.previewBarbie(service: .unknown)
    RemoteWidgetEntry.previewBarbie(false, service: .apple)
    RemoteWidgetEntry.previewTheater(service: .apple)
}

#Preview("No Subscription", as: .systemMedium) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}
