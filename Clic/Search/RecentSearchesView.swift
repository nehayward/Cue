import SwiftUI
import SonosKit

struct RecentSearchesView: View {
    @Environment(Router.self) private var router: Router
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    @State private var recentSearches = RecentSearchesStorage.shared

    var body: some View {
        let items = recentSearches.object.reversed()
        if !items.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(items), id: \.id) { item in
                            Menu {
                                Button(role: .destructive) {
                                    withAnimation {
                                        recentSearches.object.removeAll { $0 == item }
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ContentArtworkView(content: item, preferredSize: 70)
                                        .frame(width: 70, height: 70)
                                        .clipped()
                                    Text(item.title)
                                        .font(.caption)
                                        .fontDesign(.rounded)
                                        .lineLimit(1)
                                        .frame(width: 70)
                                }
                            } primaryAction: {
                                navigate(to: item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                HStack {
                    Text("Recent")
                        .fontDesign(.rounded)
                        .bold()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        withAnimation {
                            recentSearches.clear()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func navigate(to item: PlayableContent) {
        switch item.content.type {
        case .artist, .libraryArtist:
            router.navigate(to: .artistDetail(content: item, group: selectedGroupService?.group))
        case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
            router.navigate(to: .mediaDetail(content: item, group: selectedGroupService?.group))
        default:
            break
        }
    }
}
