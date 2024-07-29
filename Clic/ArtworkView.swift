import NukeUI
import SwiftUI
import SonosKit

struct ArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @State private var size: Double = 24
    @State private var alarmRunning: Bool = false
    @State var imageRequest: ImageRequest?

    private var placeholderSize: Double { size == 24 ? 100 : 42 }

    var body: some View {
        GeometryReader { proxy in
            LazyImage(request: imageRequest) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if state.isLoading {
                    Rectangle()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.ultraThinMaterial)
                        .shadow(radius: 2)
                        .transition(.opacity)
                } else {
                    Rectangle()
                        .foregroundStyle(.accent.gradient.secondary)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.coordinatorRoom.track.artworkURL == nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.regularMaterial)
                                    .frame(width: placeholderSize, height: placeholderSize)
                            }
                        }
                }
            }
            // MARK: For Screenshots
//            #if DEBUG
//            .overlay {
//                Rectangle()
//                    .foregroundStyle(.regularMaterial)
//            }
//            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
            .overlay(alignment: .bottomTrailing) {
                ArtworkBadgeView(group: $group, size: $size, alarmRunning: $alarmRunning)
            }
            .onChange(of: proxy.size, initial: true) {
                if proxy.size.width < 100 {
                    size = 16
                } else {
                    size = 24
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.spring, value: group.coordinatorRoom.track.trackID)
            .onChange(of: group.rooms.contains(where: \.alarmRunning), initial: true) { old, new in
                alarmRunning = new
            }
            .task(id: group.coordinatorRoom.track.id) {
                guard let url = group.coordinatorRoom.track.artworkURL else {
                    imageRequest = nil
                    return
                }
                let request = URLRequest(url: url)
                imageRequest = ImageRequest(urlRequest: request)
            }
        }
    }
}
//
//#Preview("Empty") {
//    ArtworkView(track: .constant(Track(trackID: "", name: "", TVMode: false)))
//        .environment(SonosService.shared)
//}
//
//#Preview("Dua Lipa") {
//    ArtworkView(track: .constant(Track(trackID: "6wf7Yu7cxBSPrRlWeSeK0Q", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
//#Preview("White Background") {
//    ArtworkView(track: .constant(Track(trackID: "204669559", musicService: .apple)))
//        .environment(SonosService.shared)
//
//}
//
//#Preview("Dark Album") {
//    ArtworkView(track: .constant(Track(trackID: "7sjuNUjWtSqhbxJ3RAUffm", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
