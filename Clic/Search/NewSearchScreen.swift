import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct NewSearchScreen: View, KeyboardReadable {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) var parentRouter: Router?

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var router: Router = Router()
    @State private var isKeyboardVisible = false
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil

    @FocusState private var searchFocused: Bool
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    @CloudStorage(CloudKeys.playHistory) private var playHistory: OrderedSet<PlayableContent> = [] {
        didSet {
            playHistory = OrderedSet(playHistory.prefix(15))
        }
    }

    @State private var musicSearchService = MusicSearchService()

    var group: GroupRoom?
    var instant: Bool = false

    var body: some View {
        Group {
            switch appleMusicAuthorized {
            case .authorized:
                NavigationStack(path: $router.path) {
                    List {
                        if !searchCompletionTapped {
                            ForEach(musicSearchService.suggestions) { suggestion in
                                Button {
                                    musicSearchService.query = suggestion.searchTerm
                                    self.suggestion = suggestion.searchTerm
                                    searchCompletionTapped = true
                                    searchFocused = false
                                } label: {
                                    HStack {
                                        Image(systemName: "magnifyingglass")
                                        Text(suggestion.displayTerm)
                                        Spacer()
                                    }
                                    .foregroundStyle(.accent)
                                }
                            }
                        }

                        if !playHistory.isEmpty, musicSearchService.query.isEmpty {
                            PlayHistoryView()
                                .environment(router)
                                .environment(group)
                        }

                        if musicSearchService.query.isEmpty {
                            FavoritesView()
                                .environment(router)
                                .environment(group)
                        }

                        if !musicSearchService.query.isEmpty {
                            switch musicSearchSelection {
                            case .spotify:
                                SpotifySearchView(isAdding: false, addingContent: .constant(nil), spotifyResult: $musicSearchService.spotifyResult, filters: $filters, group: group)
                            case .apple:
                                ForEach(musicSearchService.topResults) { result in
                                    AppleMusicSearchScreen(result: result, filters: $filters, group: group)
                                        .fontDesign(.rounded)
                                }
                            }
                        }
                        Rectangle()
                            .foregroundStyle(.clear)
                            .frame(height: 100)
                            .listRowSeparator(.hidden)

                    }
                    .ignoresSafeArea(.keyboard)
                    .headerProminence(.increased)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            TextField("Search", text: $musicSearchService.query, prompt: Text("Searching \(musicSearchSelection.title) \t\t\t\t"))
                                .focused($searchFocused)
                                .textFieldStyle(.roundedBorder)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel) {
                                if musicSearchService.query.isEmpty {
                                    dismiss()
                                    parentRouter?.inspectorSheet = nil
                                } else {
                                    musicSearchService.query.removeAll()
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("")
                    .withAppRouter(router: router)
                    .task(id: musicSearchService.query + musicSearchSelection.rawValue) {
                        if suggestion == nil {
                            searchCompletionTapped = false
                        }
//                        if appleMusicAuthorized == .notDetermined { return }
                        await musicSearchService.search(for: musicSearchSelection)
                        suggestion = nil
                    }
                    .animation(.interactiveSpring, value: musicSearchService.topResults)
                    .animation(.interactiveSpring, value: searchCompletionTapped)
                    .onReceive(keyboardPublisher) { newIsKeyboardVisible in
                        if musicSearchService.query.isEmpty {
                            withAnimation {
                                isKeyboardVisible = newIsKeyboardVisible
                                searchCompletionTapped = !newIsKeyboardVisible
                            }
                        }
                    }
                    .onDisappear {
                        if musicSearchService.query.isEmpty {
                            Task { @MainActor in
                                searchFocused = false
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        HStack {
                            FilterView(filters: $filters)
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
                        }
                        .padding([.vertical, .trailing])
                        .background {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                    }
                }
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
#if !os(visionOS)
                .scrollDismissesKeyboard(.immediately)
#endif
                .presentationDragIndicator(.hidden)
                .scrollContentBackground(.hidden)
                .listStyle(.inset)
                .environment(router)
                .onChange(of: router.dismiss) {
                    dismiss()
                }
            case .notDetermined:
                AppleMusicPermissionsView()
                    .environment(musicSearchService)
                    .addDismiss(action: dismiss.callAsFunction)
            case .denied:
                ImprovedSearch(adding: .constant(nil), group: group)
            }
        }
        .onAppear {
            if musicSearchService.query.isEmpty {
                appleMusicAuthorized = musicSearchService.getMusicAuthorization()
                Task {
                    await sonosService.getFavoriteList()
                }
            }
            if instant {
                searchFocused = true
                showKeyboard()
            }
        }
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(400))
            UIView.setAnimationsEnabled(true)
        }
//        var transaction = Transaction()
//        transaction.animation = .easeInOut(duration: 0)
////        transaction.animation?.speed(1)
//        withTransaction(transaction) {
//            searchIsPresented = true
//        }
    }
}

#Preview {
    NewSearchScreen(group: nil)
        .environment(SonosService.shared)
}

