import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var widgetFamily: WidgetFamily

    @ViewBuilder
    var body: some View {
        if let speakerIP = entry.configuration.room {
            switch widgetFamily {
            case .accessoryRectangular:
                RemoteWidgetRectangularView(entry: entry)
            case .accessoryCircular:
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: "playpause.circle.fill")
                }
                .containerBackground(.black, for: .widget)
            default:
                HStack {
                    VStack(spacing: 0) {
                        Label(speakerIP.name, systemImage: "hifispeaker.fill")
                            .foregroundStyle(.thickMaterial)
                            .padding(.bottom, 8)
                        HStack(spacing: 18) {
                            VStack(spacing: 12) {
                                Button(intent: PlayPauseIntent(room: speakerIP)) {
                                    Image(systemName: "playpause.fill")
                                        .padding(2)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.circle)
                                .tint(.secondary)

                                Button(intent: NextIntent(room: speakerIP)) {
                                    Image(systemName: "forward.fill")
                                        .padding(2)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.circle)
                                .tint(.secondary)

                            }
                            VStack(spacing: 12) {
                                Button(intent: SetRelativeGroupVolumeIntent(room: speakerIP, volume: 3)) {
                                    Image(systemName: "plus")
                                        .bold()
                                        .foregroundStyle(.thickMaterial)
                                        .frame(width: 40, height: 40)
                                }
                                Button(intent: SetRelativeGroupVolumeIntent(room: speakerIP, volume: -3)) {
                                    Image(systemName: "minus")
                                        .bold()
                                        .foregroundStyle(.thickMaterial)
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .background(.secondary, in: Capsule())
                        }
                        .padding(.bottom, 8)

                        HStack {
                            Image(systemName: "speaker.wave.3.fill", variableValue: entry.volume/100)
                                .foregroundStyle(.thickMaterial)
                                .contentTransition(.symbolEffect(.automatic))
                                .font(.caption)
                            ProgressView(value: Double(entry.volume), total: 100)
                                .tint(.accentColor)
                            Text("\(entry.volume, specifier: "%0.f")")
                                .foregroundStyle(.thickMaterial)
                                .font(.caption)
                                .contentTransition(.numericText())
                        }
                        .padding([.leading,.trailing])
                    }
                }
                .buttonStyle(.plain)
                .fontDesign(.rounded)
                .containerBackground(.black, for: .widget)
                .environment(\.colorScheme, .light)
            }
        } else {
            Label("Please select a room.", systemImage: "hifispeaker")
                .containerBackground(.thickMaterial, for: .widget)
        }
    }
}

#Preview(as: .systemSmall) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", name: "Garage", ip: "", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}
