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
            if !appleMusicBrowseService.userPlaylists.isEmpty {
                TileGrid(items: Array(appleMusicBrowseService.userPlaylists.prefix(TileGrid.fillCount)))
            }
        }
        .task {
            await appleMusicBrowseService.updateUsersApplePlaylists(offset: 0, limit: TileGrid.fillCount)
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

