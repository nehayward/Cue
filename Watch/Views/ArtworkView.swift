import SwiftUI

/// A cover from `ArtworkStore`, fetched the first time it's shown, with a
/// glyph until it's here: a note, or a book's.
struct ArtworkView: View {
    let url: URL?
    var symbol = "music.note"

    var body: some View {
        let artwork = ArtworkStore.shared
        Group {
            if let image = artwork.image(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: symbol)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            artwork.load(url)
        }
    }
}

/// A ring that fills as a download comes down.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.4), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
