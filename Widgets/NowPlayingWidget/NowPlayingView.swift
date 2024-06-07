import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct NowPlayingWidgetView: View {
    var entry: NowPlayingProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            NowPlayingWidgetViewMedium(entry: entry)
        default:
            if let info = entry.info {
                Label(info.room.name, systemImage: "hifispeaker.fill")
                    .symbolRenderingMode(.hierarchical)
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                Text(info.track)
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)

                .fontDesign(.rounded)
                .containerBackground(.thickMaterial, for: .widget)
                
            } else {
                VStack {
                    Text("No Wifi")
                        .containerBackground(.fill.tertiary, for: .widget)
                }
            }
        }
    }
}

struct NowPlayingWidgetViewMedium: View {
    var entry: NowPlayingProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let info = entry.info,
           let room = entry.info?.room {

            HStack(alignment: .top) {
                if let data = entry.info?.data,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 10)
                }
                VStack(alignment: .leading) {
                    Label(info.room.name, systemImage: "hifispeaker.fill")
                        .blendMode(.hardLight)
                    Text(info.track)
                        .blendMode(.hardLight)
                        .bold()
                        .lineLimit(2)
                    Text(info.artist)
                        .blendMode(.hardLight)
                        .lineLimit(1)

                }
                Spacer()
            }
            .fontDesign(.rounded)
            .containerBackground(for: .widget) {
                if let data = entry.info?.data,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .blur(radius: 20)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            Rectangle()
                                .foregroundStyle(.ultraThinMaterial)
                        }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack {
                    Button(intent: TogglePlaybackIntent(room: room)) {
                        Image(systemName: "playpause.fill")
                            .padding(2)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)

                    Button(intent: NextIntent(room: room)) {
                        Image(systemName: "forward.fill")
                            .padding(2)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                }
            }
        } else {
            VStack {
                Text("Nothing playing")
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now,
                    configuration: .init(),
                    info: NowPlayingEntry.Info(room: SonosDeviceEntity(id: "", ip: "", name: "Kitchen"),
                                               data: UIImage.barbie.jpegData(compressionQuality: 1),
                                               track: "Dance the Night (From The Barbie Album)",
                                               artist: "Dua Lipa")
    )
}
