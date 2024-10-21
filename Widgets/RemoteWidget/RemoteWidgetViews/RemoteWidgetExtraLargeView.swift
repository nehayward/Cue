
import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetExtraLargeView: View {
    var entry: Provider.Entry

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
                        Toggle(isOn: theater.nightMode, intent: NightModeIntent(room: room, nightMode: !theater.nightMode)) {
                            Label("Night Mode", systemImage: "moon.zzz")
                        }
                        .symbolVariant(theater.nightMode ? .fill : .none)
                        .labelStyle(.iconOnly)
                        .contentShape(.circle)
                        .toggleStyle(.button)
                        .foregroundStyle(.thickMaterial)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.thickMaterial)
                        .frame(width: 40, height: 40)
                        .tint(.secondary)
                        .background(theater.nightMode ? .primary : .tertiary, in: Capsule())

                        Toggle(isOn: theater.dialogLevel, intent: SpeechEnhancementIntent(room: room, speechEnhancement: !theater.dialogLevel)) {
                            Label("Speech Enhancement", systemImage: "person.wave.2")
                        }
                        .symbolVariant(theater.dialogLevel ? .fill : .none)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .contentShape(.circle)
                        .foregroundStyle(.thickMaterial)
                        .frame(width: 40, height: 40)
                        .tint(.secondary)
                        .background(theater.dialogLevel ? .primary : .tertiary, in: Capsule())
                    }
                } else {
                    HStack {
                        if let image = ArtworkManager.shared.getImage(name: entry.name ?? room.name) {
                            Image(uiImage: image)
                                .resizable()
                                .backdeployedWidgetAccentedRenderingMode(.fullColor)
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 100, height: 100)
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
                                .frame(width: 100, height: 100)
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
                            HStack {
                                Image(systemName: entry.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: entry.volume/100)
                                    .contentTransition(.symbolEffect(.automatic))
                                    .font(.caption)
                                ProgressView(value: Double(entry.volume), total: 100)
                                    .tint(.accent)
                                    .invalidatableContent()
                                    .widgetAccentable()
                                    .opacity(entry.isMuted ? 0.3 : 1)
                                Text("\(entry.volume, specifier: "%0.f")")
                                    .font(.caption)
                                    .contentTransition(.numericText())
                                    .invalidatableContent()
                                    .strikethrough(entry.isMuted)
                            }
                            .padding([.leading,.trailing])
                        }
                        .lineLimit(0, reservesSpace: true)
                        Spacer()
                        VStack(spacing: 12) {
                            Button(intent: SetRelativeGroupVolumeIntent(room: room, volume: 3)) {
                                Image(systemName: "plus")
                                    .bold()
                                    .foregroundStyle(.thickMaterial)
                                    .frame(width: 40, height: 40)
                                    .widgetAccentable()
                            }
                            Button(intent: SetRelativeGroupVolumeIntent(room: room, volume: -3)) {
                                Image(systemName: "minus")
                                    .bold()
                                    .foregroundStyle(.thickMaterial)
                                    .frame(width: 40, height: 40)
                                    .widgetAccentable()
                            }
                        }
                        .background(.primary, in: Capsule())
                        .buttonStyle(.plain)
                        .fontDesign(.rounded)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(entry.playHistory.prefix(6)) { playHistory in
                            HStack {
                                Image(systemName: playHistory.content.type.symbol)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
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
                        .fontDesign(.rounded)
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

#Preview("Active Subscription", as: .systemExtraLarge) {
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
