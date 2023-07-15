import SwiftUI
import MusicSearchKit
import SonosKit

struct MusicSearchScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var musicSearchService = MusicSearchService()
    @State var query: String = ""
    @State var results: [ItunesResult] = []
    @State private var searchTask: Task<Void, Error>?
    @Binding var room: GroupRoom?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { result in
                    HStack {
                        AsyncImage( url: URL(string: result.artworkURL),
                                    transaction: Transaction(animation: .snappy)
                                ) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .frame(width: 60, height: 60)
                                    default:
                                        RoundedRectangle(cornerRadius: 12)
                                            .foregroundStyle(.thinMaterial)
                                            .frame(width: 60, height: 60)
                                    }
                                }
                        VStack(alignment: .leading) {
                            Text(result.trackName)
                            Text(result.artistName)
                        }.onTapGesture {

                            room?.rooms[0].track = Track(name: result.trackName, artist: result.artistName, album: result.album, musicService: .apple, duration: TimeInterval(result.durationInMiliSeconds), playbackPosition: .zero)
                            dismiss()
                            Task {
                                await sonosService.queue(song: "\(result.trackID)", on: room!.rooms[0].ip)
                                guard let artworkURL = await sonosService.getArtwork(song: result.trackName, artist: result.artistName, album: result.album) else {
                                    return
                                }
                                room?.rooms[0].track.artworkURL = artworkURL
                            }
                        }
                        
                    }
                    .fontDesign(.rounded)
                }
            }
            .searchable(text: $query)
            .onChange(of: query) { oldValue, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    results = await musicSearchService.search(song: query, artist: "")
                }
            }
            .onAppear {
                searchTask?.cancel()
                searchTask = Task {
                    results = await musicSearchService.search(song: query, artist: "")
                }
            }
        }
    }
}

#Preview {
    MusicSearchScreen(room: .constant(GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")])))
        .environment(SonosService())
}

