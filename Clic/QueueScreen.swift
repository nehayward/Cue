import SwiftUI
import MusicSearchKit
import SonosKit

struct QueueScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var tracks: [Track] = []
    var group: GroupRoom

    var body: some View {
        NavigationStack {
            List {
                ForEach(tracks) { track in
                    VStack(alignment: .leading) {
                        Text(track.name)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .task {
            self.tracks = await sonosService.getQueue(ip: group.coordinatorRoom.ip)
        }
        .presentationBackground(.thinMaterial)
    }
}

#Preview {
    Text("Queue...")
        .sheet(isPresented: .constant(true)) {
            QueueScreen(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "192.168.4.50", name: "Garage")]))
                .environment(SonosService())
                .presentationDetents([.medium, .large])
        }
}

