import CloudStorage
import MusicSearchKit
import Defaults
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
                let filteredResults = filters.filter(\.isFiltered).isEmpty ?
                appleSearchResults :
                appleSearchResults.filter { item in
                    filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type)
                }

                Group {
                    ForEach(filteredResults) { item in
                        VStack {
                            PlayableContentView(item: item)
                        }
                    }
                }
                .animation(.bouncy, value: filters)
                .animation(.bouncy, value: appleSearchResults)
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
