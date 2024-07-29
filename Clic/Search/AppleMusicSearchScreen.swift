import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct AppleMusicSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(MusicSearchService.self) var musicSearchService

    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    var appleSearchResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        Group {
            switch appleMusicAuthorized {
            case .authorized:
                Group {
                    if filters.filter(\.isFiltered).isEmpty {
                        ForEach(appleSearchResults) { item in
                            PlayableContentView(item: item)
                        }
                    } else {
                        ForEach(appleSearchResults) { item in
                            if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                                PlayableContentView(item: item)
                            }
                        }
                    }
                }
                .fontDesign(.rounded)
            case .notDetermined, .denied:
                AppleMusicPermissionsView()
                    .addDismiss(action: dismiss.callAsFunction)
            }
        }
        .onAppear {
            appleMusicAuthorized = musicSearchService.getMusicAuthorization()
        }
    }
}
