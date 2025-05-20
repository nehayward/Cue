import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct TVArtworkBadgeView: View {
    var group: GroupRoom
    var alarmRunning: Bool
    
    @State private var size: Double = 0
    
    var body: some View {
        VStack {
            if alarmRunning{
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.gradient)
                    .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
                    .shadow(radius: 12)
                    .padding([.bottom, .trailing], padding)
            } else {
                if group.playbackService == .radio {
                    Image(systemName: "radio.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white.gradient)
                        .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
                        .shadow(radius: 12)
                        .padding([.bottom, .trailing], padding)
                } else {
                    group.coordinatorRoom.track.musicService.icon
                        .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
                        .padding([.bottom, .trailing], padding)
                }
            }
        }.onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            print(newValue)
            self.size = newValue.width 
        }

    }
    
    private var frameSize: Double {
        max(48, size * 0.5)
    }
    
    private var padding: Double {
        max(12, size * 0.2)
    }
}
