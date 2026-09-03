import MusicSearchKit
import SwiftUI
import SonosKit

struct LibrarySearchView: View {
    @Environment(\.dismiss) var dismiss

    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(Router.self) private var router: Router

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
