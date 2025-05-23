import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct PlayableListView: View {
    @State private var isLoading: Bool = false
    @State private var isFirstLoadEmpty: Bool = false
    @State var items: OrderedSet<PlayableContent> = []
    @State private var loadingTask: Task<Void, Never>?

    var action: ((Int) async -> ([PlayableContent]))? = nil

    var body: some View {
        List {
            ForEach(items) { item in
                PlayableContentView(item: item)
                    .onAppear {
                        // Only trigger when this is the last item and we haven't reached the end
                        if item == items.last, !isLoading, !isFirstLoadEmpty {
                            loadingTask?.cancel()
                            loadingTask = Task {
                                await loadMore()
                            }
                        }
                    }
            }
        }
        .miniPlayerOnScrollHandler()
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task {
            loadingTask?.cancel()
            loadingTask = Task {
                await initialLoad()
            }
        }
        .onDisappear {
            loadingTask?.cancel()
        }
        .overlay {
            if isLoading && items.isEmpty {
                ProgressView()
                    .padding()
                    .background(.thickMaterial)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Data Loading Methods

    private func initialLoad() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let newItems = await action?(0) else { return }
        
        // Check if task was cancelled
        guard !Task.isCancelled else { return }

        if newItems.isEmpty {
            isFirstLoadEmpty = true
        } else {
            items.append(contentsOf: newItems)
        }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let newItems = await action?(items.count) else { return }
        
        // Check if task was cancelled
        guard !Task.isCancelled else { return }

        if newItems.isEmpty {
            isFirstLoadEmpty = true
            return
        }
        
        items.append(contentsOf: newItems)
    }
}
