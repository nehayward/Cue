import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetRectangularView: View {
    var entry: Provider.Entry

    var body: some View {
        if let room = entry.configuration.room {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(room.name, systemImage: "hifispeaker.fill")
                        .padding(.leading)

                    HStack(spacing: 0) {
                        Button(intent: TogglePlaybackIntent(room: room)) {
                            Image(systemName: "playpause.fill")
                                .padding(2)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.clear)

                        Button(intent: NextIntent(room: room)) {
                            Image(systemName: "forward.fill")
                                .padding(2)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.clear)
                        HStack(spacing: 0) {
                            Button(intent: SetRelativeGroupVolumeIntent(room: room, volume: -3)) {
                                Image(systemName: "minus")
                                    .bold()
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 32)
                            }
                            Button(intent: SetRelativeGroupVolumeIntent(room: room, volume: 3)) {
                                Image(systemName: "plus")
                                    .bold()
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "speaker.wave.3.fill", variableValue: entry.volume/100)
                            .foregroundStyle(.primary)
                            .contentTransition(.symbolEffect(.automatic))
                            .font(.caption)
                            .padding(.leading)
                        ProgressView(value: Double(entry.volume), total: 100)
                            .tint(.accentColor)
                        Text("\(entry.volume, specifier: "%0.f")")
                            .foregroundStyle(.primary)
                            .font(.caption)
                            .contentTransition(.numericText())
                            .padding(.trailing)
                    }
                }
            }
            .fontDesign(.rounded)
            .buttonStyle(.borderless)
            .containerBackground(.secondary, for: .widget)
            .widgetURL(URL(string: "clic://device?id=\(room.id)"))
        } else {
            Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }
            
    }
}


#Preview(as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Garage", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}
