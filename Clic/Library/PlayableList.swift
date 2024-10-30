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

    @Binding var items: OrderedSet<PlayableContent>
    var action: ((Int) async -> ())? = nil

    var body: some View {
        List {
            ForEach(items) { item in
                PlayableContentView(item: item)
                    .task {
                        if items.firstIndex(of: item) ?? 0 >= items.count / 2 {
                            Task {
                                await action?(items.count)
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
}
