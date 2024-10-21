import CloudStorage
import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var widgetFamily: WidgetFamily

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
                            if let theater = entry.TVSettings {
                                VStack(spacing: 12) {
                                    Toggle(isOn: theater.nightMode, intent: NightModeIntent(room: room, nightMode: !theater.nightMode)) {
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

                                    Toggle(isOn: theater.dialogLevel, intent: SpeechEnhancementIntent(room: room, speechEnhancement: !theater.dialogLevel)) {
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
                                VStack(spacing: 12) {
                                    Button(intent: TogglePlaybackIntent(room: room)) {
                                        Image(systemName: "playpause.fill")
                                            .font(.caption)
                                            .foregroundStyle(.thickMaterial)
                                            .frame(width: 40, height: 40)
                                            .widgetAccentable()
                                    }
                                    .buttonBorderShape(.circle)
                                    .background(.primary, in: Capsule())

                                    Button(intent: NextIntent(room: room)) {
                                        Image(systemName: "forward.fill")
                                            .font(.caption)
                                            .foregroundStyle(.thickMaterial)
                                            .frame(width: 40, height: 40)
                                            .widgetAccentable()
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
                        }
                        .padding(.bottom, 8)

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
                    .buttonStyle(.plain)
                    .fontDesign(.rounded)
                    .containerBackground(.widgetBackground, for: .widget)
                    .widgetURL(entry.activeSubscription ? URL(string: "clic://device?id=\(room.id)") : nil)
                }
            } else {
                VStack {
                    Image(systemName: "hifispeaker.fill")
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
