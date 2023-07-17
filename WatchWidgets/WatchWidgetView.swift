import Foundation
import SwiftUI

struct WatchWidgetsEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        Image("Icon")
            .resizable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
