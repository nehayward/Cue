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
            // Stable: a fresh UUID re-tagged the row on every pass.
            .tag("applePlaylistsHeader")
            // Rows, as Recently Played draws under it on the Apple Library
            // page, not three cards splitting the row: on a wide window each
            // card grew to a third of the window and the section filled it.
            PlayableContentGridView(items: Array(appleMusicBrowseService.userPlaylists), limit: 6)
                .listRowBackground(Color.clear)
        }
        .task {
            await appleMusicBrowseService.updateUsersApplePlaylists(offset: 0, limit: 6)
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

