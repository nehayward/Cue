import CloudStorage
import MusicSearchKit
import NukeUI
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct ImprovedSearch: View, KeyboardReadable {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(\.dismiss) private var dismiss

    private let musicSearchService = MusicSearchService()

    @Binding var adding: PlayableContent?
    var isAdding: Bool = false
    
    @State private var router: Router = Router()
    @State private var isKeyboardVisible = false
    @State var query: String = ""
    @State var results: [ItunesResult] = []
    @State var spotifyResult: SpotifyResult?
    @State private var searchTask: Task<Void, Error>?
    @State private var searchFieldIsPresented: Bool = false
    @State private var searchSuggestion = Task<Void, Error>{}
    
    @State var filters = [
        FilterSelection(filter: .albums, isFiltered: false),
//        FilterSelection(filter: .artist, isFiltered: false),
        FilterSelection(filter: .songs, isFiltered: false),
        FilterSelection(filter: .playlists, isFiltered: false),
    ]

    @FocusState private var focusedField: Bool

    @AppStorage("com.clic.searchSelection") private var musicSearchSelection: SearchSelection = .spotify
    @CloudStorage("com.clic.searchHistory") var searchHistory: OrderedSet<String> = []
    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    var group: GroupRoom?
    var instant: Bool = false

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if !searchFieldIsPresented, !playHistory.isEmpty {
                    PlayHistoryView()
                        .environment(router)
                        .environment(group)
                }
                if !searchFieldIsPresented {
                    FavoritesView()
                        .environment(router)
                        .environment(group)
                }
                switch musicSearchSelection {
                case .spotify:
                    SpotifySearchView(isAdding: isAdding, addingContent: $adding, spotifyResult: $spotifyResult, filters: $filters, group: group)
                case .apple:
                    ClassicAppleMusicSearchView(results: $results, filters: $filters, group: group)
                }
                AppleMusicPermissionsView()
                    .environment(musicSearchService)
                    .listRowSeparator(.hidden)
            }
            .withAppRouter(router: router)
            .searchable(text: $query, isPresented: $searchFieldIsPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Searching \(musicSearchSelection.title)")
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
                    if !searchHistory.isEmpty {
                        Button {
                            searchHistory.removeAll()
                        } label: {
                            Text("Clear History")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .headerProminence(.increased)
            .onReceive(keyboardPublisher) { newIsKeyboardVisible in
                print("Is keyboard visible? ", newIsKeyboardVisible)
                isKeyboardVisible = newIsKeyboardVisible
            }
            .onChange(of: query, initial: true) { old, new in
//                searchSuggestion.cancel()
//                searchSuggestion = Task { @MainActor in
//                    try await Task.sleep(for: .milliseconds(100))
//                    let results = try await musicSearchService.searchSuggestion(query: query)
//                }

                let shouldDebounce = new.count - old.count < 2
                searchTask?.cancel()
                print("Searching... \(query)")
                switch musicSearchSelection {
                case .spotify:
                    searchTask = Task { @MainActor in
                        try await Task.sleep(for: .milliseconds(shouldDebounce ? 200 : 0))
                        spotifyResult = await musicSearchService.searchSpotify(query: query)
                    }
                case .apple:
                    searchTask = Task {
                        try await Task.sleep(for: .milliseconds(shouldDebounce ? 200 : 0))
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
            .navigationTitle("Search")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if !query.isEmpty {
                        if musicSearchSelection == .spotify {
                            FilterView(filters: $filters)
                        }
                    }
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
                        .id(SearchSelection.spotify)

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
                        .id(SearchSelection.apple)
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
                .background(.bar)
            }
            .addDismiss {
                dismiss()
            }
        }
        .keyboardType(.asciiCapable)
        .autocorrectionDisabled()
        #if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
        .scrollContentBackground(.hidden)
        .interactiveDismissDisabled(isKeyboardVisible)
        .listStyle(.inset)
        .onAppear {
            if instant {
                searchFieldIsPresented = true
                showKeyboard()
            }
        }
        .onDisappear {
            if !query.isEmpty {
                searchHistory = OrderedSet(searchHistory.prefix(10))
                playHistory = OrderedSet(playHistory.prefix(20))
                searchHistory.remove(query)
                searchHistory.insert(query, at: 0)
            }
        }
        .environment(router)
        .onChange(of: router.dismiss) {
            dismiss()
        }
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(400))
            UIView.setAnimationsEnabled(true)
        }
    }
}

#Preview {
    Text("Searching...")
        .sheet(isPresented: .constant(true)) {
            ImprovedSearch(adding: .constant(nil), query: "", group: .garage)
                .environment(SonosService.shared)
        }
}

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
//
