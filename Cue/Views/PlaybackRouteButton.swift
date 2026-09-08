import Defaults
import SonosKit
import SwiftUI

/// The AirPlay-style route picker: where playback goes, chosen once and
/// remembered, rather than asked for on every Play.
///
/// Deliberately content-free. It sets the destination and nothing else — the
/// same thing an AirPlay button does — so it can sit somewhere permanent like
/// the mini player instead of being tied to one piece of media. `Play` then
/// reads the saved choice through `PlayDestinationRouter` and never prompts.
///
/// Choosing while something is playing moves it: `PlaybackRoute` carries the
/// queue across, picks up at the same spot, and stops the source.
struct PlaybackRouteButton: View {
    /// Read off the singleton rather than the environment: this sits in the tab
    /// bar accessory, which is hosted outside the tab content and so isn't
    /// guaranteed to inherit what `withEnvironments()` installs. `@Observable`
    /// still tracks the `sorted` access below, so the list stays live.
    private var sonosService: SonosService { .shared }
    private var route: PlaybackRoute { .shared }

    var body: some View {
        let destination = route.destination

        Menu {
            Button {
                select(.device)
            } label: {
                Label("This Device", systemImage: "iphone.radiowaves.left.and.right")
                if destination == .device {
                    Image(systemName: "checkmark")
                }
            }

            let groups = sonosService.sorted
            if groups.isEmpty {
                Text("No speakers found")
            } else {
                Section("Speakers") {
                    ForEach(groups) { group in
                        Button {
                            select(.group(group.coordinatorID))
                        } label: {
                            Label(
                                group.nameWithCount,
                                systemImage: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill"
                            )
                            if destination == .group(group.coordinatorID) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            // Cue's own speaker-with-arrow symbol for "this device" rather
            // than the AirPlay glyph: the route is Cue's, not AirPlay's.
            Group {
                if destination == .device {
                    Image("hifispeaker.arrow.forward.fill")
                } else {
                    Image(systemName: "hifispeaker.fill")
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel("Play On")
        }
        .menuIndicator(.hidden)
        // Re-read on every appearance: the share extension writes this too, so
        // the app can come back to a destination it didn't pick itself.
        .onAppear { route.refresh() }
    }

    private func select(_ target: PlayDestination) {
        if target == .device, !FeatureGate.shared.unlock(.onDevicePlayback) { return }
        HapticManager.shared.fireHaptic(.selection)
        PlaybackRoute.shared.switchTo(target)
    }
}

#Preview {
    PlaybackRouteButton()
        .withEnvironments()
}
