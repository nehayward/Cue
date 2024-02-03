import CloudStorage
import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var widgetFamily: WidgetFamily
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        ZStack {
            if let room = entry.configuration.room {
                switch widgetFamily {
                case .accessoryRectangular:
                    RemoteWidgetRectangularView(entry: entry)
                case .accessoryCircular:
                    RemoteWidgetAccessoryCircularView(entry: entry)
                    // MARK: TODO
//                case .systemMedium:
//                    if let documentsDirectory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.clic") {
//                        let fileURL = documentsDirectory.appendingPathComponent("test.png")
//                        Text(fileURL.absoluteString)
//                        if let data = try? Data(contentsOf: fileURL) {
//                            Text("\(data.count)")
//                            if let image =  UIImage(data: data) {
//                                Image(uiImage: image)
//                            }
//                        }
//                    }
                default:
                    VStack(spacing: 0) {
                        Text(entry.name ?? room.name)
                            .font(.subheadline)
                            .padding(.bottom, 8)
                        HStack(spacing: 18) {
                            if let TVSettings = entry.TVSettings {
                                VStack(spacing: 12) {
                                    Toggle(isOn: TVSettings.nightMode, intent: NightModeIntent(room: room, nightMode: !TVSettings.nightMode)) {
                                        Label("Night Mode", systemImage: "moon.zzz")
                                    }
                                    .symbolVariant(TVSettings.nightMode ? .fill : .none)
                                    .labelStyle(.iconOnly)
                                    .contentShape(.circle)
                                    .toggleStyle(.button)
                                    .foregroundStyle(.thickMaterial)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(.thickMaterial)
                                    .frame(width: 40, height: 40)
                                    .tint(.secondary)
                                    .background(TVSettings.nightMode ? .primary : .tertiary, in: Capsule())

                                    Toggle(isOn: TVSettings.dialogLevel, intent: SpeechEnhancementIntent(room: room, speechEnhancement: !TVSettings.dialogLevel)) {
                                        Label("Speech Enhancement", systemImage: "person.wave.2")
                                    }
                                    .symbolVariant(TVSettings.dialogLevel ? .fill : .none)
                                    .labelStyle(.iconOnly)
                                    .toggleStyle(.button)
                                    .contentShape(.circle)
                                    .foregroundStyle(.thickMaterial)
                                    .frame(width: 40, height: 40)
                                    .tint(.secondary)
                                    .background(TVSettings.dialogLevel ? .primary : .tertiary, in: Capsule())
                                }
                            } else {
                                VStack(spacing: 12) {
                                    Button(intent: TogglePlaybackIntent(room: room)) {
                                        Image(systemName: "playpause.fill")
                                            .font(.caption)
                                            .foregroundStyle(.thickMaterial)
                                            .frame(width: 40, height: 40)
                                    }
                                    .buttonBorderShape(.circle)
                                    .tint(.secondary)
                                    .background(.primary, in: Capsule())

                                    Button(intent: NextIntent(room: room)) {
                                        Image(systemName: "forward.fill")
                                            .font(.caption)
                                            .foregroundStyle(.thickMaterial)
                                            .frame(width: 40, height: 40)
                                    }
                                    .buttonBorderShape(.circle)
                                    .tint(.secondary)
                                    .background(.primary, in: Capsule())
                                }
                            }
                            VStack(spacing: 12) {
                                Button(intent: SetRelativeGroupVolumeIntent(room: room, volume: 3)) {
                                    Image(systemName: "plus")
                                        .bold()
                                        .foregroundStyle(.thickMaterial)
                                        .frame(width: 40, height: 40)
                                }
                                Button(intent: SetRelativeGroupVolumeIntent(room: room, volume: -3)) {
                                    Image(systemName: "minus")
                                        .bold()
                                        .foregroundStyle(.thickMaterial)
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .background(.primary, in: Capsule())
                        }
                        .padding(.bottom, 8)

                        HStack {
                            Image(systemName: "speaker.wave.3.fill", variableValue: entry.volume/100)
                                .contentTransition(.symbolEffect(.automatic))
                                .font(.caption)
                            ProgressView(value: Double(entry.volume), total: 100)
                                .tint(.accent)
                                .invalidatableContent()
                            Text("\(entry.volume, specifier: "%0.f")")
                                .font(.caption)
                                .contentTransition(.numericText())
                                .invalidatableContent()
                        }
                        .padding([.leading,.trailing])
                    }
                    .buttonStyle(.plain)
                    .fontDesign(.rounded)
                    .containerBackground(.widgetBackground, for: .widget)
                    .widgetURL(URL(string: "clic://device?id=\(room.id)"))
                }
            } else {
                VStack {
                    Image(systemName: "hifispeaker")
                        .imageScale(.large)
                    Text("Choose Room")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .fontDesign(.rounded)
                }
                .containerBackground(.thinMaterial, for: .widget)
            }
        }
    }
}

#Preview("Small", as: .systemSmall) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Garage", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0, TVMode: false))
}

#Preview("Circle", as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "", 
                name: "Garage",
                volume: 20
            )
        ),
        volume: 20,
        track: .empty
    )
}

#Preview("Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Garage",
                volume: 20
            )
        ),
        volume: 20,
        track: .empty
    )
}

#Preview("Unlocked Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Garage",
                volume: 20
            )
        ),
        volume: 20,
        track: .empty
    )
}
