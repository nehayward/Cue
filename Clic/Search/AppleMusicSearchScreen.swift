import MusicSearchKit
import Defaults
import SwiftUI
import SonosKit

struct AppleMusicSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(MusicSearchService.self) var musicSearchService

    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    var results: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        Group {
            switch appleMusicAuthorized {
            case .authorized:
                ForEach(results.filtered(by: filters)) { item in
                    PlayableContentView(item: item)
                }
                .animation(.bouncy, value: filters)
                .animation(.bouncy, value: results)
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
