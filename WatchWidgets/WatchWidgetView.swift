import Foundation
import SwiftUI
import WidgetKit

struct WatchWidgetsEntryView: View {
    var entry: NowPlayingProvider.Entry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "hifispeaker.fill")
                .symbolRenderingMode(.hierarchical)
                .fontDesign(.rounded)
                .font(.largeTitle)
        }
        .containerBackground(.foreground, for: .widget)
    }
}



#Preview(as: .accessoryCircular) {
    WatchWidget()
} timeline: {
    NowPlayingEntry(date: .now, configuration: WatchConfigurationIntent(), info: .init(name: "Kitchen"))
}
