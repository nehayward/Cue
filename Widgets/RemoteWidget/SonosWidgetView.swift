import SwiftUI
import WidgetKit

struct SonosWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var widgetFamily: WidgetFamily

    @ViewBuilder
    var body: some View {
        if let speakerIP = entry.configuration.speakerIP {
            switch widgetFamily {
            case .accessoryRectangular:
                SonosWidgetLockScreenEntryView(entry: entry)
            case .accessoryCircular:
                Button(intent: PlayIntent()) {
                    Image(systemName: "playpause.circle.fill")
                }
            default:
                VStack(spacing: 0) {
                    Label(speakerIP.name, systemImage: "hifispeaker.fill")
                        .padding(.bottom, 12)
                    HStack {
                        VStack(spacing: 24) {
                            Button(intent: PlayIntent(speaker: speakerIP)) {
                                Image(systemName: "playpause.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                            
                            Button(intent: NextIntent(speaker: speakerIP)) {
                                Image(systemName: "forward.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.bottom, 12)
                        VStack(spacing: 24) {
                            Button(intent: SetVolumeIntent(speaker: speakerIP, volume: 5)) {
                                Image(systemName: "plus.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                            Button(intent: SetVolumeIntent(speaker: speakerIP, volume: -5)) {
                                Image(systemName: "minus.circle.fill")
                                    .resizable()
                                    .tint(.secondary)
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .padding(.bottom, 12)
                        
                    }
                    ProgressView(value: Double(entry.volume), total: 100)
                }
                .buttonStyle(.borderless)
                .fontDesign(.rounded)
                .containerBackground(.thickMaterial, for: .widget)
            }
        } else {
           Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.thickMaterial, for: .widget)
        }
    }
}

struct SonosWidgetLockScreenEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        if let speakerIP = entry.configuration.speakerIP {
            ZStack {
                VStack(alignment: .leading) {
                    Label(speakerIP.name, systemImage: "hifispeaker.fill")
                    HStack {
                        Button(intent: SetVolumeIntent(speaker: speakerIP, volume: -5)) {
                            Image(systemName: "minus.circle.fill")
                        }

                        Button(intent: PlayIntent(speaker: speakerIP)) {
                            Image(systemName: "playpause.circle.fill")
                        }


                        Button(intent: SetVolumeIntent(speaker: speakerIP, volume: 5)) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .font(.largeTitle)
                    ProgressView(value: Double(entry.volume), total: 100)
                }
                .buttonStyle(.borderless)
            }
            .fontDesign(.rounded)
            .containerBackground(.secondary, for: .widget)
        } else {
           Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }
    }
}
