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
struct PlaybackRouteButton: View {
    /// Read off the singleton rather than the environment: this sits in the tab
    /// bar accessory, which is hosted outside the tab content and so isn't
    /// guaranteed to inherit what `withEnvironments()` installs. `@Observable`
    /// still tracks the `sorted` access below, so the list stays live.
    private var sonosService: SonosService { .shared }

    /// Mirrors the stored destination — `PlayDestination` lives in
    /// `UserDefaults`, so the checkmarks need state here to redraw against.
    @State private var destination: PlayDestination = .device

    var body: some View {
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
            Image(systemName: destination == .device ? "airplayaudio" : "hifispeaker.fill")
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel("Play On")
        }
        .menuIndicator(.hidden)
        // Re-read on every appearance: the share extension writes this too, so
        // the app can come back to a destination it didn't pick itself.
        .onAppear { destination = PlayDestination.remembered ?? .device }
    }

    private func select(_ target: PlayDestination) {
        destination = target
        target.remember()
        // The play call sites still short-circuit to `selectedGroupService`
        // when it holds a group, so leaving it set would quietly outrank a
        // switch to This Device. Keeping the two in step makes this button the
        // one place the route is decided.
        SelectedGroupService.shared.group = switch target {
        case .device: nil
        case let .group(id): sonosService.groups.first { $0.coordinatorID == id }
        }
    }
}

#Preview {
    PlaybackRouteButton()
        .withEnvironments()
}
