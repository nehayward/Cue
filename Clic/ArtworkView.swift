import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService
    
    var isDraggable: Bool = false
    @Binding var group: GroupRoom
    @State private var alarmRunning: Bool = false
    @State private var imageRequest: ImageRequest?

    var body: some View {
        GeometryReader { proxy in
            LazyImage(request: imageRequest) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if state.isLoading {
                    Rectangle()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.ultraThinMaterial)
                } else {
                    Rectangle()
                        .foregroundStyle(.thickMaterial)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.coordinatorRoom.track.artworkURL == nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.foreground)
                                    .fontWeight(.light)
                                    .frame(width: proxy.size.width * 0.5, height: proxy.size.width * 0.5)
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
                ArtworkBadgeView(group: $group, size: proxy.size.width, alarmRunning: $alarmRunning)
            }
            .if(isDraggable) {
                $0.draggable(group.coordinatorRoom.track.toPlayable)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            .onTapGesture(count: 2) {
#if !targetEnvironment(macCatalyst)
                if group.coordinatorRoom.track.toPlayable.content.service == .apple {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        alertService.showAlert(with: "Added to Library", imageName: "star.fill")
                        try await AppleMusicAPI().favoriteSong(songId: group.coordinatorRoom.track.toPlayable.content.id)
                    }
                }
#endif
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
