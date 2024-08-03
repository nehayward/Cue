import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct PlayableLibraryList: View {
    @Environment(SonosService.self) private var sonosService

    @State private var isLoading: Bool = false

    @Binding var items: OrderedSet<PlayableContent>
    var action: (() async -> ())? = nil

    var body: some View {
        List {
            if !items.isEmpty {
                ForEach(items) { item in
                    PlayableContentView(item: item)
                }
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .opacity(0.01)
                    .task {
                        await action?()
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task {
            isLoading = true
            await action?()
            isLoading = false
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.thickMaterial)
                    .clipShape(Circle())
            }
        }
    }
}
