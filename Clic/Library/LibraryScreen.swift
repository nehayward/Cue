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

struct LibraryScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(Router.self) private var router
    @Environment(ContentToAdd.self) private var contentToAdd: ContentToAdd?

    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var betaFeatures = BetaFeatures()
    @State private var alertService = AlertService()
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    @CloudStorage(CloudKeys.playHistory) private var playHistory: OrderedSet<PlayableContent> = [] {
        didSet {
            playHistory = OrderedSet(playHistory.prefix(15))
        }
    }

    var group: GroupRoom?

    var body: some View {
        Text("Library")
    }
}

