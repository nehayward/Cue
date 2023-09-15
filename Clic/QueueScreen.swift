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
                ForEach(Array(tracks.enumerated()), id: \.element.trackID) { index, track in
                    HStack {
                        AsyncImage(
                            url: track.artworkURL,
                            transaction: Transaction(animation: .snappy)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .shadow(radius: 2)
                                    .frame(width: 60, height: 60)
                                    .overlay(alignment: .bottomTrailing) {
                                        switch track.musicService {
                                        case .apple:
                                            Image(systemName: "apple.logo")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .foregroundStyle(.thickMaterial)
                                                .frame(width: 16, height: 16)
                                                .padding([.trailing, .bottom], 4)
                                        case .spotify:
                                            Image(.spotifyLogo)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .foregroundStyle(.thickMaterial)
                                                .frame(width: 16, height: 16)
                                                .padding([.trailing, .bottom], 4)
                                        case .airplay, .unknown:
                                            EmptyView()
                                        }
                                    }
                            case .failure:
                                EmptyView()
                            default:
                                RoundedRectangle(cornerRadius: 4)
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.ultraThinMaterial)
                                    .shadow(radius: 2)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        Button {
                            print(track.name)
                            Task {
                                await sonosService.seek(trackNumber: index + 1, on: group.coordinatorRoom.ip)
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(track.name)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .task {
                        guard let artworkURL = await sonosService.getArtwork(from: track) else {
                            return
                        }

                        track.artworkURL = artworkURL
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
            QueueScreen(group: .garage)
                .environment(SonosService())
                .presentationDetents([.medium, .large])
        }
}

