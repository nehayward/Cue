import MusicSearchKit
import SwiftUI
import SonosKit

struct TidalSearchView: View {
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Environment(Router.self) var router: Router

    var results: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        ForEach(results.filtered(by: filters)) { item in
            PlayableContentView(item: item)
        }
        .animation(.bouncy, value: filters)
        .animation(.bouncy, value: results)
        .fontDesign(.rounded)
    }
}
