import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct PlayableGridScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(LibraryBrowseService.self) var browseService

    @State private var isLoading: Bool = false
    @Binding var items: OrderedSet<PlayableContent>

    var action: ((Int) async -> ())? = nil
    private let adaptiveColumn = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumn, spacing: 16) {
                ForEach(items) { item in
                    PlayableCardView(item: item)
                        .task {
                            if items.firstIndex(of: item) ?? 0 >= items.count - 1 {
                                Task {
                                    await action?(items.count)
                                }
                            }
                        }
                }
            }

            // TODO: Improve
            if items.isEmpty, !isLoading {
                ContentUnavailableView {
                    Text("No Items")
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .animation(.interactiveSpring, value: items)
        .task {
            isLoading = true
            await action?(0)
            isLoading = false
        }
    }
}
