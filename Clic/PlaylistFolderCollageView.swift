import SwiftUI
import NukeUI
import SonosKit

struct PlaylistFolderCollageView: View {
    let folderID: String
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @State private var artworkURLs: [URL] = []
    @State private var isLoading = false
    
    var body: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundStyle(.ultraThinMaterial)
            .overlay {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else if !artworkURLs.isEmpty {
                    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                        ForEach(0..<2, id: \.self) { row in
                            GridRow {
                                ForEach(0..<2, id: \.self) { column in
                                    let index = row * 2 + column
                                    if index < artworkURLs.count {
                                        LazyImage(url: artworkURLs[index]) { state in
                                            if let image = state.image {
                                                image
                                                    .resizable()
                                                    .aspectRatio(1, contentMode: .fill)
                                            } else {
                                                Rectangle()
                                                    .foregroundStyle(.quaternary)
                                                    .aspectRatio(1, contentMode: .fit)
                                            }
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Rectangle()
                                            .foregroundStyle(.quaternary)
                                            .aspectRatio(1, contentMode: .fit)
                                            .opacity(0)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.title)
                }
            }
            .task {
                await loadArtwork()
            }
    }
    
    func loadArtwork() async {
        guard !isLoading && artworkURLs.isEmpty else { return }
        
        isLoading = true
        print("Loading artwork for folder: \(folderID)")
        let urls = await appleMusicBrowseService.getPlaylistFolderContents(id: folderID, offset: 0)
        print("Got \(urls) artwork URLs for folder: \(folderID)")
        artworkURLs = urls.0.compactMap(\.artwork)
        print(artworkURLs)
        isLoading = false
    }
}
