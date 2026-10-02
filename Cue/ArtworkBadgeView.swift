import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct ArtworkBadgeView: View {
    @Environment(\.scenePhase) private var scenePhase
    var group: GroupRoom
    var alarmRunning: Bool
    @State private var padding: Double = 4
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Center artwork / symbol. Built only while an alarm is running:
            // it used to be there always, hidden with opacity, and its
            // repeating wiggle ran every frame on every speaker's artwork
            // regardless - about 300 SwiftUI updates a second with five
            // speakers, foreground or locked.
            if alarmRunning {
                alarmSymbol
            }
            
            // Bottom-trailing badge
            group.coordinatorRoom.track.musicService.icon
                .foregroundStyle(.white)
                .containerRelativeFrame(.vertical) { width, _ in
                    max(width * 0.05, 24)
                }
                .padding([.bottom, .trailing], padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .background {
            Color.clear
                .onGeometryChange(for: Double.self) { proxy in
                    proxy.size.width
                } action: { width in
                    if width > 100 {
                        padding = 8
                    } else {
                        padding = 4
                    }
                }

        }
    }

    private var alarmSymbol: some View {
        let symbol = Image(systemName: "alarm.waves.left.and.right.fill")
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white.gradient)
            .scaleEffect(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        return Group {
            if #available(iOS 18.0, macCatalyst 18.0, *) {
                // Only while someone can see it: the process outlives the
                // screen (the Lock Screen audio session keeps it running).
                symbol.symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)), isActive: scenePhase == .active)
            } else {
                symbol
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .foregroundStyle(.ultraThinMaterial)
        }
    }
}
