import SwiftUI
import NukeUI
import SonosKit

struct PlaylistFolderCollageView: View {
    let folderID: String
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @State private var artworkURLs: [URL] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            if artworkURLs.isEmpty && !isLoading {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .bold()
                    }
            } else if isLoading {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
            } else {
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        ForEach(0..<2, id: \.self) { index in
                            if index < artworkURLs.count {
                                LazyImage(url: artworkURLs[index]) { state in
                                    imageView(state: state)
                                }
                            } else {
                                Rectangle()
                                    .foregroundStyle(.clear)
                            }
                        }
                    }
                    HStack(spacing: 1) {
                        ForEach(2..<4, id: \.self) { index in
                            if index < artworkURLs.count {
                                LazyImage(url: artworkURLs[index]) { state in
                                    imageView(state: state)
                                }
                            } else {
                                Rectangle()
                                    .foregroundStyle(.clear)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadArtwork()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    @ViewBuilder
    private func imageView(state: LazyImageState) -> some View {
        if let image = state.image {
            image
                .resizable()
                .scaledToFit()
        } else if state.isLoading {
            Rectangle()
                .foregroundStyle(.gray.opacity(0.3))
                .overlay {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.5)
                }
        } else {
            // Fallback for failed/empty images
            Rectangle()
                .foregroundStyle(.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
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
