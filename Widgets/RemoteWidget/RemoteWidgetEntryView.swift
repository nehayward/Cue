import CloudStorage
import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetEntryView: View {
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
                case .systemMedium:
                    RemoteWidgetMediumView(entry: entry)
                case .systemLarge:
                    RemoteWidgetLargeView(entry: entry)
                case .systemExtraLarge:
                    RemoteWidgetExtraLargeView(entry: entry)
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
                        .symbolRenderingMode(.hierarchical)
                        .fontDesign(.rounded)
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
    RemoteWidgetEntry.previewBarbie()
}

#Preview("Circle", as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}

#Preview("Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}

#Preview("Unlocked Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}
