import MusicSearchKit
import SwiftUI
import SonosKit

struct ServiceSearchView: View {
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    
    @Environment(\.dismiss) var dismiss

    var results: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        ForEach(results.filtered(by: filters)) { item in
            PlayableContentView(item: item)
        }
    }
}
