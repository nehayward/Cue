import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct PlayableList: View {
    @Environment(SonosService.self) private var sonosService

    @State private var isLoading: Bool = false
    /// A page is on its way; no other is asked for meanwhile.
    @State private var isLoadingMore = false
    /// The last page added nothing: there's no more to ask for.
    @State private var reachedEnd = false

    @Binding var items: OrderedSet<PlayableContent>
    var action: ((Int) async -> ())? = nil

    var body: some View {
        List {
            ForEach(items) { item in
                PlayableContentView(item: item)
                    .onAppear { loadMoreIfNeeded(after: item) }
            }
        }
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task {
            isLoading = true
            await action?(0)
            isLoading = false
        }.overlay {
            if isLoading, items.isEmpty {
                ProgressView()
                    .padding()
                    .background(.thickMaterial)
                    .clipShape(Circle())
            }
        }
    }

    /// Asks for the next page once a row near the end appears, one page at
    /// a time. Every row in the bottom half used to ask for it as it
    /// appeared, so a scroll sent a burst of identical requests for the
    /// same page.
    private func loadMoreIfNeeded(after item: PlayableContent) {
        guard !isLoadingMore, !reachedEnd,
              let index = items.firstIndex(of: item), index >= items.count - 15 else { return }
        isLoadingMore = true
        let countBefore = items.count
        Task {
            await action?(items.count)
            reachedEnd = items.count == countBefore
            isLoadingMore = false
        }
    }
}
