import CloudStorage
import MusicSearchKit
import SwiftUI
import SonosKit

struct SearchHistoryView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @CloudStorage("com.cue.searchHistory") var searchHistory: Set<String> = []

    var body: some View {
        List {
            ForEach(Array(searchHistory), id: \.self) { search in
                Text(search)
                    .listRowBackground(Color.clear)
            }
        }
        .presentationBackground(.regularMaterial)
        .scrollContentBackground(.hidden)
        .presentationDetents([.large])
        .listStyle(.grouped)
    }
}

#Preview {
    Text("Searching...")
        .sheet(isPresented: .constant(true)) {
            SearchHistoryView()
                .environment(SonosService())
        }
}

