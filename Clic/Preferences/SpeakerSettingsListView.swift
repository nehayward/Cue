import Analytics
import CloudStorage
import Defaults
import SwiftUI
import SonosKit
import RevenueCat
import MusicSearchKit
import SubscriptionKit
import RevenueCatUI

struct SpeakerSettingsListView: View {
    @Environment(SonosService.self) var sonosService: SonosService

    var body: some View {
        List {
            ForEach(sonosService.sortedRooms) { room in
                NavigationLink(value: RouterDestination.speakerSettings(room: room)) {
                    HStack {
                        Image(systemName: "circle.square.fill")
                            .foregroundStyle((room.info?.color ?? "") == "Black" ? .black : .white, .quaternary)
                        Text(room.name)
                        if let info = room.info {
                            Text("(\(info.modelDisplayName))")
                        }
                    }
                }
            }
        }
        .navigationTitle("Speaker Settings")
        .toolbarTitleDisplayMode(.inline)
        .task {
            sonosService.monitor()
        }
    }
}

#Preview {
    NavigationStack {
        SpeakerSettingsListView()
    }
    .withEnvironments()
}
