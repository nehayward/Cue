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

struct ApplePlaylistsView: View {
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService

    var body: some View {
        @Bindable var appleMusicBrowseService = appleMusicBrowseService
        
        Section {
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
        } header: {
            NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $appleMusicBrowseService.userPlaylists, action: { offset in
                await appleMusicBrowseService.updateUsersApplePlaylists(offset: offset)
            })) {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
            .foregroundStyle(.secondary)
        }
        .headerProminence(.increased)
        .task {
            await appleMusicBrowseService.updateUsersApplePlaylists(offset: 0, limit: 4)
        }
        .listSectionSeparator(.hidden)
    }
}

#Preview {
    ApplePlaylistsView()
        .withEnvironments()
}

