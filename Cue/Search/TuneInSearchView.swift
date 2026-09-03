import SwiftUI
import MusicSearchKit
import SonosKit

struct TuneInSearchView: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    let results: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        ForEach(results.filtered(by: filters)) { item in
            PlayableContentView(item: item)
        }
        .fontDesign(.rounded)
    }
}
