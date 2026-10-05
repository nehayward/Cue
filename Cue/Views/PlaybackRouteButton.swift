import AVKit
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
/// The button opens `PlayOnSheet`, laid out like the system's AirPlay
/// picker: This Device and every room, each row its own volume slider. On a
/// speaker it is the group button too — a tap on a room adds it to the group
/// or drops it, the same rules the press-and-hold group menu uses. Leaving the
/// speakers altogether is This Device.
///
/// With Sonos off it is the system AirPlay button instead.
struct PlaybackRouteButton: View {
    /// Read off the singleton rather than the environment: this sits in the tab
    /// bar accessory, which is hosted outside the tab content and so isn't
    /// guaranteed to inherit what `withEnvironments()` installs.
    private var sonosService: SonosService { .shared }

    var body: some View {
        VStack {
            if sonosService.isEnabled {
                SonosRouteButton()
            } else {
                // With Sonos off the only routes are the system's, so the
                // button is the system's AirPlay picker itself. Speakers are
                // switched on in Settings ▸ Sonos.
                AirPlayRoutePicker()
                    .frame(width: 30, height: 30)
                    .accessibilityLabel("AirPlay")
            }
        }
        // Re-read on every appearance: the share extension writes this too, so
        // the app can come back to a destination it didn't pick itself.
        .onAppear { PlaybackRoute.shared.refresh() }
    }
}

/// The Play On button while Sonos is on: opens `PlayOnSheet`.
private struct SonosRouteButton: View {
    private var route: PlaybackRoute { .shared }

    @State private var isPresented = false
    @Namespace private var transition

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // Cue's own speaker-with-arrow symbol rather than the AirPlay
            // glyph: the route is Cue's, not AirPlay's.
            Image("hifispeaker.arrow.forward.fill")
                .accessibilityLabel("Play On")
                .accessibilityValue(route.group?.nameWithCount ?? "This Device")
        }
        // The sheet grows out of the button and shrinks back into it,
        // rather than sliding up from the bottom edge, far from where the
        // tap was.
        .zoomSource(.playOn, in: transition)
        .sheet(isPresented: $isPresented) {
            PlayOnSheet()
                .zoomTransition(from: .playOn, in: transition)
        }
    }
}

/// The system AirPlay button: a tap puts up the system route sheet, the
/// same one Control Center shows, and the device's audio follows it.
private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .label
        picker.activeTintColor = .tintColor
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct PendingSwitch: Identifiable {
    let target: PlayDestination
    var id: String { target.groupID ?? "device" }
}

/// The small sheet a route switch asks from: move what's playing along, or
/// only change where playback goes. "Don't ask again" writes the answer to
/// the setting (Settings › Playback), so the prompt is one tap to retire.
struct RouteTransferPrompt: View {
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
