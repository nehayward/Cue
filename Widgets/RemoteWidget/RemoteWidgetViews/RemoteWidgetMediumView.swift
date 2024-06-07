import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetMediumView: View {
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
                    Link(destination: URL(string: "clic://group?id=\(room.id)")!) {
                        Image("hifispeaker.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .bold()
                    }
                    Link(destination: URL(string: "clic://search?id=\(room.id)")!) {
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
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 60, height: 60)
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
                if let image = ArtworkManager.shared.getImage(name: entry.name ?? room.name) {
                    Image(uiImage: image)
                        .resizable()
                        .blur(radius: 20)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            Rectangle()
                                .foregroundStyle(.ultraThinMaterial)
                        }
//                        // MARK: For Screenshots
//                        #if DEBUG
//                        .overlay {
//                            Rectangle()
//                                .foregroundStyle(.regularMaterial)
//                        }
//                        #endif
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if entry.TVSettings == nil {
                    HStack {
                        Button(intent: TogglePlaybackIntent(room: room)) {
                            Image(systemName: "playpause.fill")
                                .padding(2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .buttonBorderShape(.circle)

                        Button(intent: NextIntent(room: room)) {
                            Image(systemName: "forward.fill")
                                .padding(2)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .buttonBorderShape(.circle)
                    }
                }
            }
            .fontDesign(.rounded)
            .widgetURL(URL(string: "clic://device?id=\(room.id)"))
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
