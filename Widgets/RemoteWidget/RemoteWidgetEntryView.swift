import CloudStorage
import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var widgetFamily: WidgetFamily
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @CloudStorage("com.clic.subscriptions") var activeSubscription: Bool = false

    @ViewBuilder
    var body: some View {
        ZStack {
            if let room = entry.configuration.room {
                switch widgetFamily {
                case .accessoryRectangular:
                    RemoteWidgetRectangularView(entry: entry)
                case .accessoryCircular:
                    RemoteWidgetAccessoryCircularView(entry: entry)
                default:
                    VStack(spacing: 0) {
                        Label(entry.name ?? room.name, systemImage: "hifispeaker.fill")
                            .font(.subheadline)
                            .padding(.bottom, 8)
                        HStack(spacing: 18) {
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
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Garage", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
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
