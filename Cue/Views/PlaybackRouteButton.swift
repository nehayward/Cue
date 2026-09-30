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
/// Choosing while something is playing can move it: `PlaybackRoute` carries
/// the queue across, picks up at the same spot, and stops the source. Whether
/// it does is the user's call (`QueueTransferPreference`) — by default a
/// small prompt asks, since sometimes the point of switching is to leave the
/// speaker's own queue alone.
///
/// On a speaker it is the group button too. The menu then lists every room
/// as a toggle on the group's membership — check several to play there
/// together, uncheck one to drop it — with Everywhere and Ungroup All under
/// them, the same rows the press-and-hold group menu shows. Switching to a
/// different room outright is a check and an uncheck; leaving the speakers
/// altogether is This Device.
struct PlaybackRouteButton: View {
    /// Read off the singleton rather than the environment: this sits in the tab
    /// bar accessory, which is hosted outside the tab content and so isn't
    /// guaranteed to inherit what `withEnvironments()` installs. `@Observable`
    /// still tracks the `sorted` access below, so the list stays live.
    private var sonosService: SonosService { .shared }
    private var route: PlaybackRoute { .shared }

    /// Whether to caption the icon with the group it plays on. The Now
    /// Playing toolbar has the room for it; the mini player does not.
    var showsDestinationName = false

    /// A switch waiting on the prompt's answer.
    @State private var pending: PendingSwitch?

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

            if let group = route.group {
                // On a speaker the rooms are toggles on this group, so the
                // list reads once: no group list above a room list.
                GroupMenuItems(group: group)
            } else {
                let groups = sonosService.sorted
                if !sonosService.isEnabled {
                    // The way in for someone who has never used speakers.
                    // Looking only starts from here or Settings, since it is
                    // what puts up the Local Network prompt.
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        sonosService.setEnabled(true)
                    } label: {
                        Label("Find Sonos Speakers", systemImage: "hifispeaker.2")
                    }
                } else if groups.isEmpty {
                    Text(sonosService.isSearching ? "Looking for speakers…" : "No speakers found")
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
                            }
                        }
                    }
                }
            }
        } label: {
            // With Sonos off the only routes are the system's, so it reads as
            // AirPlay. With it on, Cue's own speaker-with-arrow symbol: the
            // route is Cue's, not AirPlay's.
            Group {
                if sonosService.isEnabled {
                    Image("hifispeaker.arrow.forward.fill")
                } else {
                    Image(systemName: "airplayaudio")
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Play On")
            .accessibilityValue(route.group?.nameWithCount ?? "This Device")
        }
        .menuIndicator(.hidden)
        // Hung under the button rather than stacked with it, so the icon
        // stays level with its neighbours in the toolbar row. Outside the
        // Menu's label on purpose: iOS renders that label as one flattened
        // button image, which ignores the offset and doesn't redraw the
        // name when the group changes.
        .overlay(alignment: .bottom) {
            if showsDestinationName, let group = route.group {
                Text(group.nameWithCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 160)
                    .alignmentGuide(.bottom) { $0[.top] - 6 }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(group.nameWithCount)
            }
        }
        .sheet(item: $pending) { pending in
            RouteTransferPrompt(target: pending.target) { carrying in
                self.pending = nil
                PlaybackRoute.shared.switchTo(pending.target, carrying: carrying)
            }
        }
        // Re-read on every appearance: the share extension writes this too, so
        // the app can come back to a destination it didn't pick itself.
        .onAppear { route.refresh() }
    }

    private func select(_ target: PlayDestination) {
        if target == .device, !FeatureGate.shared.unlock(.onDevicePlayback) { return }
        HapticManager.shared.fireHaptic(.selection)
        let preference = QueueTransferPreference.current
        if preference == .ask, route.hasSomethingToCarry(to: target) {
            pending = PendingSwitch(target: target)
        } else {
            route.switchTo(target, carrying: preference != .never)
        }
    }
}

private struct PendingSwitch: Identifiable {
    let target: PlayDestination
    var id: String { target.groupID ?? "device" }
}

/// The small sheet a route switch asks from: move what's playing along, or
/// only change where playback goes. "Don't ask again" writes the answer to
/// the setting (Settings › Playback), so the prompt is one tap to retire.
private struct RouteTransferPrompt: View {
    let target: PlayDestination
    let onChoose: (_ carrying: Bool) -> Void

    @State private var dontAskAgain = false

    private var route: PlaybackRoute { .shared }

    private var sourceName: String {
        route.group?.nameWithCount ?? UIDevice.current.name
    }

    private var targetName: String {
        guard let id = target.groupID else { return UIDevice.current.name }
        return SonosService.shared.groups.first { $0.coordinatorID == id }?.nameWithCount ?? "Speaker"
    }

    private func symbol(for destination: PlayDestination) -> String {
        destination == .device ? "iphone" : "hifispeaker.fill"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: symbol(for: route.destination))
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: symbol(for: target))
            }
            .font(.title)
            .symbolRenderingMode(.hierarchical)
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text("Move What's Playing?")
                    .font(.headline)
                Text("Bring the queue from \(sourceName) to \(targetName), or switch and leave it where it is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button {
                    choose(carrying: true)
                } label: {
                    Text("Move to \(targetName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    choose(carrying: false)
                } label: {
                    Text("Just Switch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            Toggle("Don't ask again", isOn: $dontAskAgain)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .tint(.accent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func choose(carrying: Bool) {
        HapticManager.shared.fireHaptic(.selection)
        if dontAskAgain {
            let preference: QueueTransferPreference = carrying ? .always : .never
            UserDefaults.standard.set(preference.rawValue, forKey: AppStorageKeys.routeQueueTransfer)
        }
        onChoose(carrying)
    }
}

#Preview {
    PlaybackRouteButton()
        .withEnvironments()
}
