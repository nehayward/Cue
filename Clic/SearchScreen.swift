import SwiftUI
import MusicSearchKit
import SonosKit

enum SearchSelection: String, Equatable {
    case spotify
    case apple
}

struct SearchScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismissSearch) var dismissSearch
    @Environment(\.isSearching) var isSearching


    @State var musicSearchService = MusicSearchService()
    @State var query: String = ""
    @State var results: [ItunesResult] = []
    @State var spotifyResult: SpotifyResult?
    @State private var searchTask: Task<Void, Error>?
    @State private var musicSearchSelection: SearchSelection = .spotify
    @State private var searchFieldIsPresented: Bool = true
    @FocusState private var focusedField: Bool

    var group: GroupRoom
    @Environment(\.dismiss) var dismiss



    @State private var scope: SearchSelection = .spotify

    var body: some View {
        NavigationStack {
            List {
//                TextField(text: $query) {
//                    Text("HERE")
//                }
//                .focused($focusedField, equals: true)

                switch musicSearchSelection {
                case .spotify:
                    ForEach(spotifyResult?.playlists?.items ?? []) { item in
                        HStack {
                            AsyncImage( url: URL(string: item.images.first?.url ?? ""),
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
                                Text(item.id)
                                Text(item.name)
                                Text(item.uri)
//                                Text(item.href)

                            }.onTapGesture {
                                
//                                room?.rooms[0].track = Track(name: item.name, artist: result.artistName, album: result.album, musicService: .apple, duration: TimeInterval(result.durationInMiliSeconds), playbackPosition: .zero)
                                print(group.coordinatorRoom.ip)
                                dismiss()
                                print(item.id)
                                print(item.name)
                                print(item.owner.displayName)
                                Task {
                                    await sonosService.queueSpotifyPlaylist(
                                        id: item.id,
                                        title: item.name,
                                        owner: item.owner.displayName,
                                        on: group.coordinatorRoom.ip,
                                        group: group
                                    )
                                }
                            }
                            
                        }
                        .fontDesign(.rounded)
                    }
                case .apple:
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
                                dismiss()
                                Task {
                                    await sonosService.queue(song: "\(result.trackID)", on: group.coordinatorRoom.ip)
                                }
                            }

                        }
                        .fontDesign(.rounded)
                    }
                }

            }
            .searchable(text: $query,  isPresented: $searchFieldIsPresented)
            .onChange(of: query) {
                searchTask?.cancel()
                print("Searching... \(query)")
                switch musicSearchSelection {
                case .spotify:
                    searchTask = Task {
                        spotifyResult = await musicSearchService.searchSpotify(song: query, artist: "")
                    }
                case .apple:
                    searchTask = Task {
                        results = await musicSearchService.search(song: query, artist: "")
                    }
                }
            }
            .onChange(of: musicSearchSelection) {
                searchTask?.cancel()
                switch musicSearchSelection {
                case .spotify:
                    searchTask = Task {
                        spotifyResult = await musicSearchService.searchSpotify(song: query, artist: "")
                    }
                case .apple:
                    searchTask = Task {
                        results = await musicSearchService.search(song: query, artist: "")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "hifispeaker")
                        Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                    }
                    .fontDesign(.rounded)
                    .bold()
                }
            }
//            .safeAreaInset(edge: .bottom) {
//                VStack {
//
//                    TextField(
//                        "New message",
//                        text: $query
//                    )
//                    .focused($focusedField)
//                    .padding()
//                    .textFieldStyle(.roundedBorder)
//                    .background(.ultraThinMaterial)
//                    .onSubmit {
//                        // append message
//                    }
//
//                    Picker("", selection: $musicSearchSelection) {
//                        Text("Spotify")
//                            .tag(MusicSearchSelection.spotify)
//                        Text("Apple")
//                            .tag(MusicSearchSelection.apple)
//                    }
//                    .pickerStyle(.segmented)
//                    .padding()
//                    .background(.ultraThinMaterial)
//                }
//            }
//            .onSubmit {
//                print("HERE")
//            }
//            .task {
//                focusedField = true
//            }
            .searchScopes($musicSearchSelection, activation: .onSearchPresentation) {
                Text("Spotify").tag(SearchSelection.spotify)
                Text("Apple").tag(SearchSelection.apple)
//
//                Picker("", selection: $musicSearchSelection) {
//                    Text("Spotify")
//                        .tag(MusicSearchSelection.spotify)
//                    Text("Apple")
//                        .tag(MusicSearchSelection.apple)
//                }
//                .pickerStyle(.segmented)
//                .padding()
            }
        }
        .presentationBackground(.thinMaterial)

    }
}

#Preview {
    Text("Searching...")
        .fullScreenCover(isPresented: .constant(true)) {
            SearchScreen(query: "Dua Lipa", group: .garage)
                .environment(SonosService())
        }

}

