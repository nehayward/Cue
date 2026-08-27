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

struct ApplePlaylistsView: View {
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService

    var body: some View {
        @Bindable var appleMusicBrowseService = appleMusicBrowseService
        
        Section {
            NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $appleMusicBrowseService.userPlaylists, action: { offset in
                await appleMusicBrowseService.updateUsersApplePlaylists(offset: offset)
            })) {
                Text("Apple Playlists")
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .tag(UUID().uuidString)
            if !appleMusicBrowseService.userPlaylists.isEmpty {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ForEach(appleMusicBrowseService.userPlaylists.prefix(3)) { item in
                            PlayableCardView(item: item)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .task {
            await appleMusicBrowseService.updateUsersApplePlaylists(offset: 0, limit: 4)
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(0)
        .listRowInsets(.default)
    }
}

#Preview {
    let appleMusicBrowseService: AppleMusicBrowseService = AppleMusicBrowseService()
    
    List {
        ApplePlaylistsView()
    }
    .environment(appleMusicBrowseService)
    .listStyle(.plain)
    .forPreview()
    .task {
        await appleMusicBrowseService.updateUsersApplePlaylists(offset: 0)
    }
}

