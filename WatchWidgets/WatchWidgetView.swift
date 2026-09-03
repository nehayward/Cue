import Foundation
import SwiftUI
import WidgetKit

struct WatchWidgetsEntryView: View {
    var entry: NowPlayingProvider.Entry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image("cue_icon")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .widgetAccentable()
        }
        .containerBackground(.clear, for: .widget)
    }
}



#Preview(as: .accessoryCircular) {
    WatchWidget()
} timeline: {
    NowPlayingEntry(date: .now, configuration: WatchConfigurationIntent(), info: .init(name: "Kitchen"))
}
