import Foundation
import SonosKitMini
import SwiftUI

/// Cue Mini's menu: Cue's player (`CueNowPlayingCard`), on this Mac or a
/// Sonos group, the group's volume under it, and Mini's settings.
struct MiniMenuScreen: View {
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var menuVisibilityService = MenuVisibilityService.shared
    @State private var link = CueLink.shared
    @State private var isVisible = false

    /// The group Cue plays on, as the speakers here know it, for its volume
    /// in the player card: by its coordinator, or a room in it.
    private var cueGroupBinding: Binding<SonosDevice>? {
        guard link.showsSpeakers, let id = link.speakerGroupID,
              let index = sonosServiceMini.devices.firstIndex(where: { device in
                  device.id == id || device.rooms.contains { $0.id == id }
              }) else { return nil }
        return $sonosServiceMini.devices[index]
    }

    var body: some View {
        CueNowPlayingCard(isVisible: isVisible, speakerGroup: cueGroupBinding)
            .padding(.horizontal, 12)
            .frame(width: 400, alignment: .top)
            .safeArea(edge: .bottom) {
                SettingsMenuView()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }
            .fontDesign(.rounded)
            .padding(.vertical)
            .environment(sonosServiceMini)
            .task(id: link.showsSpeakers) {
                // The speakers only for the group Cue plays on and its volume.
                guard link.showsSpeakers else { return }
                try? await sonosServiceMini.loadWatch(useCache: true)
            }
            .onAppear {
                isVisible = true
                menuVisibilityService.setMenuVisible(true)
                // A fresh clock from Cue, and anything missed.
                link.send(.refresh)
            }
            .onDisappear {
                isVisible = false
                menuVisibilityService.setMenuVisible(false)
            }
    }
}

extension View {
    @ViewBuilder
    func safeArea<V>(edge: VerticalEdge, @ViewBuilder content: () -> V) -> some View where V : View {
        if #available(iOS 26.0, macOS 26, *) {
            self
                .safeAreaBar(edge: edge, content: content)
        } else {
            self
                .safeAreaInset(edge: edge, content: content)
        }
    }
}
