import Analytics
import CloudStorage
import Defaults
import SwiftUI
import SonosKit
import RevenueCat
import MusicSearchKit

struct SpeakerSettingsListView: View {
    @Environment(SonosService.self) var sonosService: SonosService

    var body: some View {
        List {
            ForEach(sonosService.sortedRooms) { room in
                NavigationLink(value: RouterDestination.speakerSettings(room: room)) {
                    HStack(spacing: 14) {
                        Image(systemName: speakerSymbol(for: room))
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(room.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let model = room.info?.modelDisplayName {
                                Text(model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Speaker Settings")
        .toolbarTitleDisplayMode(.inline)
        .task {
            sonosService.monitor()
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
    }

    private func speakerSymbol(for room: Room) -> String {
        if room.isSoundbar { return "tv.and.hifispeaker.fill" }
        return "hifispeaker.fill"
    }
}

#Preview {
    NavigationStack {
        SpeakerSettingsListView()
    }
    .withEnvironments()
}
