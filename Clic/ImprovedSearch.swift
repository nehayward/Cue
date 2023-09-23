import SwiftUI
import MusicSearchKit
import SonosKit

struct ImprovedSearch: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismissSearch) var dismissSearch
    @Environment(\.isSearching) var isSearching

    @State var selection: PresentationDetent = .large

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
                    Section {
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
                                    Text(item.name)
                                }
                                .onTapGesture {
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
                                        await sonosService.play(ip: group.coordinatorRoom.ip)
                                    }

                                }

                            }
                            .fontDesign(.rounded)
                        }
                    } header: {
                        Text("Playlist")
                    }
                    Section {
                        ForEach(spotifyResult?.tracks?.items ?? []) { item in
                            HStack {
                                AsyncImage( url: URL(string: item.album.images.first?.url ?? ""),
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
                                    Text(item.name)
                                }
                                .onTapGesture {
//                                    dismiss()
                                    Task {
                                        await sonosService.queueSpotifyTrack(id: item.id, group: group)
                                    }
                                }
//                                .onTapGesture {
//                                    print(group.coordinatorRoom.ip)
//                                    dismiss()
//                                    print(item.id)
//                                    print(item.name)
//                                    print(item.owner.displayName)
//                                    Task {
//                                        await sonosService.queueSpotifyPlaylist(
//                                            id: item.id,
//                                            title: item.name,
//                                            owner: item.owner.displayName,
//                                            on: group.coordinatorRoom.ip,
//                                            group: group
//                                        )
//                                        await sonosService.play(ip: group.coordinatorRoom.ip)
//                                    }
//
//                                }
//
                            }
                            .fontDesign(.rounded)
                        }
                    } header: {
                        Text("Tracks")
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
            .searchable(text: $query, isPresented: $searchFieldIsPresented)
            .onChange(of: query, initial: true) {
                searchTask?.cancel()
                print("Searching... \(query)")
                switch musicSearchSelection {
                case .spotify:
                    searchTask = Task {
                        try await Task.sleep(for: .milliseconds(200))
                        spotifyResult = await musicSearchService.searchSpotify(query: query)
                    }
                case .apple:
                    searchTask = Task {
                        try await Task.sleep(for: .milliseconds(200))
                        results = await musicSearchService.search(song: query, artist: "")
                    }
                }
            }
            .onChange(of: musicSearchSelection) {
                searchTask?.cancel()
                switch musicSearchSelection {
                case .spotify:
                    searchTask = Task {
                        spotifyResult = await musicSearchService.searchSpotify(query: query)
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
                        Image(systemName: "hifispeaker.fill")
                        Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                    }
                    .fontDesign(.rounded)
                    .bold()
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0){


                    Picker("", selection: $musicSearchSelection) {
                        Text("Spotify")
                            .tag(SearchSelection.spotify)
                        Text("Apple")
                            .tag(SearchSelection.apple)
                    }
                    .pickerStyle(.segmented)
                    .padding([.leading, .trailing, .top])
//                    FilterView()
//                    Picker("", selection: $musicSearchSelection) {
//                        Text("Artist")
////                            .tag(SearchSelection.spotify)
//                        Text("Song")
//                        Text("Playlist")
////                            .tag(SearchSelection.apple)
//                    }
//                    .pickerStyle(.segmented)
//                    .padding()

//                    TextField(
//                        "New message",
//                        text: $query
//                    )
//                    .focused($focusedField)
//                    .padding()
//
//                    .onSubmit {
//                        // append message
//                    }
                }
                .keyboardType(.alphabet)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .background(.ultraThinMaterial)
            }
//            .overlay(alignment: .bottomTrailing) {
//                Button {
//                    dismiss()
//                } label: {
//                    Text("Dismiss")
//                }
//
//            }
//            .onSubmit {
//                print("HERE")
//            }

        }
        .presentationBackground(.thinMaterial)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.large], selection: $selection)
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
        .presentationBackground(.thinMaterial)
        .interactiveDismissDisabled(focusedField)
        .listStyle(.inset)
        .onAppear {
            showKeyboard()
        }
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        focusedField = true
        Task {
            try await Task.sleep(for: .milliseconds(400))
            UIView.setAnimationsEnabled(true)
        }
    }
}

#Preview {
    Text("Searching...")
        .sheet(isPresented: .constant(true)) {
            ImprovedSearch(query: "Dua Lipa", group: .garage)
                .environment(SonosService())
            
        }

}

