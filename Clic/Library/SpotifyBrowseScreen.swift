import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults
import TipKit
import AuthenticationServices

struct SpotifyBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var router = Router()
    @State private var isLoading = true

    var body: some View {

        Button("Sign In") {
            Task {
                do {
                    let urlWithToken = try await webAuthenticationSession.authenticate(using: SpotifyAuthorization.shared.authorize(), callbackURLScheme: "spotifyAuthorization", preferredBrowserSession: .shared)
                    print(urlWithToken)
                    if let components = URLComponents(url: urlWithToken, resolvingAgainstBaseURL: false) {
                        let queryItems = components.queryItems

                        if let code = queryItems?.first(where: { $0.name == "code" })?.value,
                           let state = queryItems?.first(where: { $0.name == "state" })?.value {
                            print("Code: \(code)")
                            print("State: \(state)")
                            let auth = try? await SpotifyAuthorization.shared.fetchSpotifyToken(code: code, state: state)
                            print(auth)

                        } else {
                            print("Code or state not found in the URL")
                        }
                    } else {
                        print("Invalid URL")
                    }
                } catch {
                    print(error.localizedDescription)
                    // code to handle authentication errors
                }
            }
        }
    }
}

//        @Bindable var appleMusicBrowseService = appleMusicBrowseService
//        NavigationStack(path: $router.path) {
//            ScrollView {
//                VStack(alignment: .leading) {
//                    Section {
//                        if !appleMusicBrowseService.userPlaylists.isEmpty {
//                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
//                                ForEach(appleMusicBrowseService.userPlaylists.prefix(5)) { item in
//                                    PlayableCardView(item: item)
//                                }
//                            }
//                        }
//                    } header: {
//                        HStack {
//                            Text("Playlists")
//                                .font(.title)
//                            Spacer()
//                            NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $appleMusicBrowseService.userPlaylists, action: { offset in
//                                await appleMusicBrowseService.updateUsersApplePlaylists()
//                            })) {
//                                Text("Show all \(Image(systemName: "chevron.right"))")
//                            }
//                        }
//                        .foregroundStyle(.secondary)
//                        .padding(.vertical)
//                    }
//
//                    HStack {
//                        Text("Recently Played")
//                            .font(.title)
//                        Spacer()
//                        NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Played", items: $appleMusicBrowseService.usersRecents, action: { offset in
//                            await appleMusicBrowseService.updateUsersRecentPlayed(offset: offset)
//                        })) {
//                            Text("Show all \(Image(systemName: "chevron.right"))")
//                        }
//                    }
//                    .foregroundStyle(.secondary)
//                    .padding(.vertical)
//
//                    if !appleMusicBrowseService.usersRecents.isEmpty {
//                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
//                            ForEach(appleMusicBrowseService.usersRecents.prefix(5)) { item in
//                                PlayableCardView(item: item)
//                            }
//                        }
//                    }
//
//                    HStack {
//                        Text("Albums")
//                            .font(.title)
//                        Spacer()
//                       Text("Coming Soon…")
//                    }
//                    .foregroundStyle(.secondary)
//                    .padding(.vertical)
//                }
//            }
//            .contentMargins(.horizontal, 16, for: .scrollContent)
//            .fontDesign(.rounded)
//            .foregroundStyle(.primary)
//            .withAppRouter(router: router)
//            .navigationTitle("Apple Library")
//            .navigationBarTitleDisplayMode(.inline)
//            .task {
//                await updateAppleMusicBrowseService()
//            }
//            .addDismiss(action: dismiss.callAsFunction)
//        }
//        .overlay {
//            if isLoading {
//                ProgressView()
//                    .frame(maxWidth: .infinity, alignment: .center)
//                    .listRowBackground(Color.clear)
//            }
//        }
//        .environment(router)
//        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
//            Task {
//                await updateAppleMusicBrowseService()
//            }
//        }

//    @MainActor
//    private func updateAppleMusicBrowseService() async {
//        isLoading = true
//        await appleMusicBrowseService.updateUsersApplePlaylists()
//        await appleMusicBrowseService.updateUsersRecentPlayed()
////        await appleMusicBrowseService.updateUsersAppleAlbums()
////        await appleMusicBrowseService.updateUsersAppleArtists()
//        isLoading = false
//    }
//}

//#Preview {
//    SpotifyBrowseScreen()
//        .withEnvironments()
//}

