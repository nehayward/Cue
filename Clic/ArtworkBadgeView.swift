import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkBadgeView: View {
    var group: GroupRoom
    var alarmRunning: Bool
    
    var size: Double = 100
    
    var body: some View {
        ZStack {
            if alarmRunning{
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
                    .padding([.bottom, .trailing], padding)
            } else {
                if group.playbackService == .radio {
                    Image(systemName: "radio.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
                        .padding([.bottom, .trailing], padding)
                } else {
                    group.coordinatorRoom.track.musicService.icon
                        .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
                        .padding([.bottom, .trailing], padding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var frameSize: Double {
        max(16, size * 0.1)
    }
    
    private var padding: Double {
        max(4, size * 0.04)
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
