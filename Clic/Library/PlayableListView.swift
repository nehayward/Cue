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
    @Environment(SonosService.self) private var sonosService

    @State private var isLoading: Bool = false
    @State private var isFirstLoadEmpty: Bool = false

    @State var items: OrderedSet<PlayableContent> = []
    
    var action: ((Int) async -> ([PlayableContent]))? = nil

    var body: some View {
        List {
            ForEach(items) { item in
                VStack {
                    PlayableContentView(item: item)
                        .task {
                            if items.firstIndex(of: item) ?? 0 >= items.count / 2, !isFirstLoadEmpty {
                                Task {
                                    guard let newItems = await action?(items.count), !newItems.isEmpty else {
                                        if items.isEmpty { isFirstLoadEmpty = true }
                                        return
                                    }
                                    items.append(contentsOf: newItems)
                                }
                            }
                        }
                }
            }
        }
        .miniPlayerOnScrollHandler()
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task {
            isLoading = true
            if let newItems = await action?(0) {
                items.append(contentsOf: newItems)
            }
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
}
