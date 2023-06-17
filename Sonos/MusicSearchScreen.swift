import SwiftUI
import MusicSearchKit

struct MusicSearchScreen: View {
    @State var musicSearchService = MusicSearchService()
    @State var query: String = "Dua Lipa"
    @State var results: [ItunesResult] = []
    @State private var searchTask: Task<Void, Error>?


    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { result in
                    HStack {
                        AsyncImage( url: URL(string: result.artworkURL),
                                    transaction: Transaction(animation: .snappy)
                                ) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .frame(width: 60, height: 60)
                                    default:
                                        RoundedRectangle(cornerRadius: 12, style: /*@START_MENU_TOKEN@*/.continuous/*@END_MENU_TOKEN@*/)
                                            .foregroundStyle(.thinMaterial)
                                            .frame(width: 60, height: 60)
                                    }
                                }
                        VStack(alignment: .leading) {
                            Text(result.trackName)
                            Text(result.album)
                            Text(result.artistName)
                            Text(result.type)
                        }
                    }
                    .fontDesign(.rounded)
                }
            }
            .searchable(text: $query)
            .navigationTitle("Search")
            .onChange(of: query) { oldValue, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    results = await musicSearchService.search(song: query, artist: "")
                }
            }
            .onAppear {
                searchTask?.cancel()
                searchTask = Task {
                    results = await musicSearchService.search(song: query, artist: "")
                }
            }
        }
    }
}

#Preview {
    MusicSearchScreen()
}

