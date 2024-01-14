import CloudStorage
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit
import Kingfisher

struct MusicSearchScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService

//    private let musicSearchService = MusicSearchService()

//    @State private var isKeyboardVisible = false
//    @State var query: String = ""
//    @State var results: [ItunesResult] = []
//    @State var spotifyResult: SpotifyResult?
//    @State private var searchTask: Task<Void, Error>?
//    @State private var searchFieldIsPresented: Bool = true
//    @FocusState private var focusedField: Bool

//    @AppStorage("com.clic.searchSelection") private var musicSearchSelection: SearchSelection = .spotify
//    @CloudStorage("com.clic.searchHistory") var searchHistory: OrderedSet<String> = []

    var body: some View {
        Text("Music")
//        List {
//            Text("HERE")
////            if let playlists = spotifyResult?.playlists?.items {
////                playlist(playlists: playlists)
////            }
//            //                switch musicSearchSelection {
//            //                case .spotify:
//            //                    guard let playlists = spotifyResult?.playlists else { return }
//            //                    playlist(playlists: playlists)
//            //                case .apple:
//            //                    AppleMusicSearchView(results: $results, filters: $filters, group: group)
//            //                }
//        }
//        .padding(.bottom, 60)
//        .searchable(text: $query, isPresented: $searchFieldIsPresented, prompt: "Searching \(musicSearchSelection.title)")
//        .searchSuggestions {
//            if query.isEmpty {
//                ForEach(Array(searchHistory), id: \.self) { suggestion in
//                    Text(suggestion)
//                        .swipeActions {
//                            Button(role: .destructive) {
//                                searchHistory.remove(suggestion)
//                            } label: {
//                                Label("Delete", systemImage: "trash")
//                            }
//                        }
//                        .searchCompletion(suggestion)
//                }
//                if !searchHistory.isEmpty {
//                    Button {
//                        searchHistory.removeAll()
//                    } label: {
//                        Text("Clear History")
//                            .bold()
//                            .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .listRowSeparator(.hidden)
//                }
//            }
//        }
//        .onReceive(keyboardPublisher) { newIsKeyboardVisible in
//            print("Is keyboard visible? ", newIsKeyboardVisible)
//            isKeyboardVisible = newIsKeyboardVisible
//        }
//        .onChange(of: query, initial: true) { old, new in
//            let shouldDebounce = new.count - old.count < 2
//            searchTask?.cancel()
//            print("Searching... \(query)")
//            switch musicSearchSelection {
//            case .spotify:
//                searchTask = Task { @MainActor in
//                    try await Task.sleep(for: .milliseconds(shouldDebounce ? 200 : 0))
//                    spotifyResult = await musicSearchService.searchSpotify(query: query)
//                }
//            case .apple:
//                searchTask = Task {
//                    try await Task.sleep(for: .milliseconds(shouldDebounce ? 200 : 0))
//                    results = await musicSearchService.search(song: query, artist: "")
//                }
//            }
//        }
//        .onChange(of: musicSearchSelection) {
//            searchTask?.cancel()
//            switch musicSearchSelection {
//            case .spotify:
//                searchTask = Task { @MainActor in
//                    spotifyResult = await musicSearchService.searchSpotify(query: query)
//                }
//            case .apple:
//                searchTask = Task {
//                    results = await musicSearchService.search(song: query, artist: "")
//                }
//            }
//        }
//        .navigationBarTitleDisplayMode(.inline)
//        .ignoresSafeArea(.keyboard, edges: .bottom)
//
//        .safeAreaInset(edge: .bottom) {
//            HStack {
//                Spacer()
//                Menu {
//                    Button {
//                        musicSearchSelection = .spotify
//                    } label: {
//                        HStack {
//                            Text("Spotify")
//                            Image(.spotifyLogo)
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .tag(SearchSelection.spotify)
//                                .frame(width: 24, height: 24)
//                        }
//                    }
//                    .id(SearchSelection.spotify)
//
//                    Button {
//                        musicSearchSelection = .apple
//                    } label: {
//                        HStack {
//                            Text("Apple Music")
//                            Image(systemName: "apple.logo")
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .tag(SearchSelection.spotify)
//                                .frame(width: 24, height: 24)
//                        }
//                    }
//                    .id(SearchSelection.apple)
//                } label: {
//                    switch musicSearchSelection {
//                    case .spotify:
//                        Image(.spotifyLogo)
//                            .resizable()
//                            .aspectRatio(contentMode: .fit)
//                            .tag(musicSearchSelection)
//                            .frame(width: 24, height: 24)
//                    case .apple:
//                        Image(systemName: "apple.logo")
//                            .resizable()
//                            .aspectRatio(contentMode: .fit)
//                            .tag(SearchSelection.spotify)
//                            .frame(width: 24, height: 24)
//                    }
//                }
//                .frame(alignment: .trailing)
//                .padding()
//            }
//            .background(.bar)
//        }
//        .keyboardType(.asciiCapable)
//        .autocorrectionDisabled()
//        .scrollDismissesKeyboard(.immediately)
//        .interactiveDismissDisabled(isKeyboardVisible)
//        .listStyle(.inset)
//        .onDisappear {
//            if !query.isEmpty {
//                searchHistory = OrderedSet(searchHistory.prefix(10))
//                searchHistory.remove(query)
//                searchHistory.insert(query, at: 0)
//            }
//        }
    }

    private func playlist(playlists: [SpotifyPlaylistItems]) -> some View {
        Section {
            ForEach(playlists) { item in
                Button {
//                    dismiss()
                    Task {

                    }
                } label: {
                    HStack {
                        AsyncImage(url: URL(string: item.images.first?.url ?? ""),
                                   transaction: Transaction(animation: .snappy)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipped()
                            default:
                                RoundedRectangle(cornerRadius: 12)
                                    .foregroundStyle(.thinMaterial)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.owner.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Playlist")
        }
    }
}
//
//#Preview {
//    Text("Searching...")
//        .sheet(isPresented: .constant(true)) {
//            ImprovedSearch(query: "Dua Lipa", group: .garage)
//                .environment(SonosService())
//        }
//}
//
//#Preview("Empty Queue") {
//    Text("Searching Empty...")
//        .sheet(isPresented: .constant(true)) {
//            ImprovedSearch(query: "", group: .garage)
//                .environment(SonosService())
//        }
//}
//
//#Preview("Full Screen") {
//    Text("Searching Empty...")
//        .fullScreenCover(isPresented: .constant(true)) {
//            ImprovedSearch(query: "", group: .garage)
//                .environment(SonosService())
//        }
//}

