import Analytics
import CloudStorage
import Defaults
import SwiftUI
import WatchConnectivity
import SonosKit
import RevenueCat
import MusicSearchKit
import SubscriptionKit
import RevenueCatUI
import MessageUI

struct SpeakerSettingsListView: View {
    @Environment(SonosService.self) var sonosService: SonosService

    var body: some View {
        List {
            ForEach(sonosService.sortedRooms) { room in
                NavigationLink(room.name, value: RouterDestination.speakerSettings(room: room))
            }
        }
        .navigationTitle("Speaker Settings")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    SpeakerSettingsListView()
}
