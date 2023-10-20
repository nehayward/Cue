import CloudStorage
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit
import Kingfisher

struct ImprovedSearch: View, KeyboardReadable {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismissSearch) var dismissSearch
    @Environment(\.isSearching) var isSearching
    @Environment(\.dismiss) var dismiss

    @State private var isKeyboardVisible = false
    @State var selection: PresentationDetent = .large

    @State var musicSearchService = MusicSearchService()
    @State var query: String = ""
    @State var results: [ItunesResult] = []
    @State var spotifyResult: SpotifyResult?
    @State private var searchTask: Task<Void, Error>?
    @State private var searchFieldIsPresented: Bool = true
    @FocusState private var focusedField: Bool

    @AppStorage("com.clic.searchSelection") private var musicSearchSelection: SearchSelection = .spotify
    @CloudStorage("com.clic.searchHistory") var searchHistory: OrderedSet<String> = []

    var group: GroupRoom

    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack {
            List {
                switch musicSearchSelection {
                case .spotify:
                    if let playlists = spotifyResult?.playlists?.items {
                        Section {
                            ForEach(playlists) { item in
                                Button {
                                    print(group.coordinatorRoom.ip)
                                    //                                    dismiss()
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
                                } label: {
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
                                    }
                                }.fontDesign(.rounded)
                            }
                        } header: {
                            Text("Playlist")
                        }
                    }

                    if let tracks = spotifyResult?.tracks?.items {
                        Section {
                            ForEach(tracks) { item in
                                Button {
                                    dismiss()
                                    Task {
                                        await sonosService.queueSpotifyTrack(id: item.id, group: group)
                                    }
                                } label: {
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
                                    }
                                    .fontDesign(.rounded)
                                }
                            }
                        } header: {
                            Text("Tracks")
                        }
                    }

                    // TODO: Add back when you can queue
                    //                    if let albums = spotifyResult?.albums?.items {
                    //                        albumRow(albums: albums)
                    //                    }
                    //                    if let artists = spotifyResult?.artists?.items {
                    //                        ArtistRow(artists: artists)
                    //                    }
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
            .searchable(text: $query, isPresented: $searchFieldIsPresented, prompt: "Searching \(musicSearchSelection.title)")
            .searchSuggestions {
                if query.isEmpty {
                    ForEach(Array(searchHistory), id: \.self) { suggestion in
                        Text(suggestion)
                            .swipeActions {
                                Button(role: .destructive) {
                                    searchHistory.remove(suggestion)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .searchCompletion(suggestion)
                    }
                }
            }
            .onReceive(keyboardPublisher) { newIsKeyboardVisible in
                print("Is keyboard visible? ", newIsKeyboardVisible)
                isKeyboardVisible = newIsKeyboardVisible
            }
            .onChange(of: query, initial: true) {
                searchTask?.cancel()
                print("Searching... \(query)")
                switch musicSearchSelection {
                case .spotify:
                    searchTask = Task { @MainActor in
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
                    searchTask = Task { @MainActor in
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
                HStack {
                    Spacer()
                    Menu {
                        Button {
                            musicSearchSelection = .spotify
                        } label: {
                            HStack {
                                Text("Spotify")
                                Image(.spotifyLogo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .tag(SearchSelection.spotify)
                                    .frame(width: 24, height: 24)
                            }
                        }

                        Button {
                            musicSearchSelection = .apple
                        } label: {
                            HStack {
                                Text("Apple Music")
                                Image(systemName: "apple.logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .tag(SearchSelection.spotify)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    } label: {
                        switch musicSearchSelection {
                        case .spotify:
                            Image(.spotifyLogo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .tag(musicSearchSelection)
                                .frame(width: 24, height: 24)
                        case .apple:
                            Image(systemName: "apple.logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .tag(SearchSelection.spotify)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(alignment: .trailing)
                    .padding()
                }
                //                    FilterView()
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
                //
                //
                //                .textFieldStyle(.roundedBorder)
                //                .background(.ultraThinMaterial)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .keyboardType(.asciiCapable)
        .autocorrectionDisabled()
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.large], selection: $selection)
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
        .scrollContentBackground(.hidden)
        .interactiveDismissDisabled(isKeyboardVisible)
        .listStyle(.inset)
        .onAppear {
            showKeyboard()
        }
        .onDisappear {
            if !query.isEmpty {
                searchHistory.insert(query, at: 0)
            }
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

    private func ArtistRow(artists: [SpotifyArtistsItems]) -> some View {
        Section {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(artists) { item in
                        VStack {
                            AsyncImage( url: URL(string: item.images.first?.url ?? ""),
                                        transaction: Transaction(animation: .snappy)
                            ) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                default:
                                    RoundedRectangle(cornerRadius: 12)
                                        .foregroundStyle(.thinMaterial)
                                        .frame(width: 60, height: 60)
                                }
                            }
                            VStack(alignment: .leading) {
                                Text(item.name)
                            }
                        }
                        .fontDesign(.rounded)
                        .onTapGesture {
                            dismiss()
                            Task {
                                await sonosService.queueSpotifyTrack(id: item.id, group: group)
                                //                            await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("Artist")
        }
    }

    private func albumRow(albums: [SpotifyAlbumItems]) -> some View {
        Section {
            ForEach(albums) { album in
                HStack {
                    AsyncImage( url: URL(string: album.images.first?.url ?? ""),
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
                        Text(album.name)
                    }
                    .onTapGesture {
                        //                        dismiss()
                        Task {
                            await sonosService.queueSpotifyTrack(id: album.id, group: group)
                        }
                    }
                }
                .fontDesign(.rounded)
            }
        } header: {
            Text("Albums")
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

#Preview("Empty Queue") {
    Text("Searching Empty...")
        .sheet(isPresented: .constant(true)) {
            ImprovedSearch(query: "", group: .garage)
                .environment(SonosService())
        }
}

#Preview("Full Screen") {
    Text("Searching Empty...")
        .fullScreenCover(isPresented: .constant(true)) {
            ImprovedSearch(query: "", group: .garage)
                .environment(SonosService())
        }
}

