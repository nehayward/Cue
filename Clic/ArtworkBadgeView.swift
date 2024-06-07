import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkBadgeView: View {
    @Binding var group: GroupRoom
    @Binding var size: Double
    @Binding var alarmRunning: Bool

    var body: some View {
        if alarmRunning{
            Image(systemName: "alarm.waves.left.and.right.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.gradient)
                .frame(width: size, height: size, alignment: .bottomTrailing)
                .padding(size == 24 ? 16 : 4)
                .shadow(radius: 10)
        } else {
            if group.playbackService == .radio {
                Image(systemName: "radio.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white.gradient)
                    .frame(width: size, height: size, alignment: .bottomTrailing)
                    .padding(size == 24 ? 16 : 4)
                    .shadow(radius: 10)
            } else {
                group.coordinatorRoom.track.musicService.icon
                    .frame(width: size, height: size, alignment: .bottomTrailing)
                    .padding(size == 24 ? 16 : 4)
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
