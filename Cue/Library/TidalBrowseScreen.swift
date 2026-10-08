import MusicSearchKit
import SonosKit
import SwiftUI

/// Tidal's front page in the library: the signed-in account's My Collection
/// — songs, albums, artists and playlists — and the albums added to it most
/// recently. Everything here plays on this device through TIDAL's own
/// player, and on a speaker that has Tidal linked in the Sonos app.
struct TidalBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var router = Router.browse
    @State private var account = TidalAccount.shared
    @State private var recentAlbums: [PlayableContent] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if account.isSignedIn {
                    ForEach([TidalLibrary.Kind.songs, .albums, .artists, .playlists], id: \.self) { kind in
                        NavigationLink(value: kind.destination) {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                    }

                    if !recentAlbums.isEmpty {
                        Section {
                            Text("Recently Added Albums")
                                .fontDesign(.rounded)
                                .fontWeight(.semibold)

                            LazyVGrid(columns: [.init(), .init()]) {
                                ForEach(recentAlbums.prefix(10)) { item in
                                    PlayableContentRowView(item: item)
                                        .buttonStyle(.plain)
                                        .geometryGroup()
                                }
                            }
                        }
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .overlay {
                if !account.isSignedIn {
                    signedOutView
                }
            }
            .listSectionSpacing(4)
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .animation(.default, value: recentAlbums)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .miniPlayerOnScrollHandler()
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Tidal")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: account.isSignedIn) {
                await loadRecentAlbums()
            }
            .refreshable {
                await loadRecentAlbums()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                        .environment(router)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MediaSelector()
                        .environment(router)
                }
            }
#if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
#endif
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task { await loadRecentAlbums() }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    /// The first page of the collection's albums, newest first.
    private func loadRecentAlbums() async {
        guard account.isSignedIn else {
            recentAlbums = []
            return
        }
        isLoading = true
        recentAlbums = await TidalLibrary.shared.page(.albums, offset: 0)
        isLoading = false
    }

    private var signedOutView: some View {
        ContentUnavailableView {
            Label("Not Signed In", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Sign in to Tidal to browse your collection and play it here or on your Sonos speakers.")
        } actions: {
            Button {
                router.presentedSheet = .tidalManagement
            } label: {
                Text("Sign In")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    TidalBrowseScreen()
        .withEnvironments()
        .environment(SelectedGroupService(group: nil))
}
