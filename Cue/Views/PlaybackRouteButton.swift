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
/// With Sonos off, or on cellular where no speaker can be reached, it is the
/// system AirPlay button instead.
struct PlaybackRouteButton: View {
    /// How much of the place the system's AirPlay button takes, all of it a
    /// target. A Sonos button's comes from the `buttonStyle` around it.
    var airPlaySide: CGFloat = 30

    /// Read off the singleton rather than the environment: this sits in the tab
    /// bar accessory, which is hosted outside the tab content and so isn't
    /// guaranteed to inherit what `withEnvironments()` installs.
    private var sonosService: SonosService { .shared }

    var body: some View {
        VStack {
            if sonosService.isAvailable {
                SonosRouteButton()
            } else {
                // With Sonos off, or away from Wi‑Fi, the only routes are the
                // system's, so the button is the system's AirPlay picker
                // itself. Speakers are switched on in Settings ▸ Sonos.
                // In a car the sound goes to CarPlay, and the button shows a
                // car where the AirPlay glyph was, the way Music's does. The
                // picker underneath still takes the tap.
                AirPlayRoutePicker(hidesGlyph: sonosService.isInCar)
                    .frame(width: airPlaySide, height: airPlaySide)
                    .overlay {
                        if sonosService.isInCar {
                            Image(systemName: "car.fill")
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("AirPlay")
                    .accessibilityValue(sonosService.isInCar ? "CarPlay" : AudioOutputName.shared.name ?? "")
            }
        }
        // Re-read on every appearance: the share extension writes this too, so
        // the app can come back to a destination it didn't pick itself.
        .onAppear { PlaybackRoute.shared.refresh() }
    }
}

/// The Play On button while Sonos is on: opens `PlayOnSheet`.
private struct SonosRouteButton: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var route: PlaybackRoute { .shared }

    @State private var isPresented = false
    @Namespace private var transition

    /// Where there's room, a popover from the button, as the system's
    /// AirPlay picker is on iPad; a sheet zooming out of it otherwise.
    private var presentsPopover: Bool {
        horizontalSizeClass == .regular
    }

    private var showsSheet: Binding<Bool> {
        Binding(get: { isPresented && !presentsPopover }, set: { isPresented = $0 })
    }

    private var showsPopover: Binding<Bool> {
        Binding(get: { isPresented && presentsPopover }, set: { isPresented = $0 })
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // Cue's own speaker-with-arrow symbol rather than the AirPlay
            // glyph: the route is Cue's, not AirPlay's.
            Image("hifispeaker.arrow.forward.fill")
                .accessibilityLabel("Play On")
                .accessibilityValue(route.group?.nameWithCount ?? AudioOutputName.shared.name ?? ThisDevice.name)
        }
        // The sheet grows out of the button and shrinks back into it,
        // rather than sliding up from the bottom edge, far from where the
        // tap was.
        .zoomSource(.playOn, in: transition)
        .sheet(isPresented: showsSheet) {
            PlayOnSheet()
                .zoomTransition(from: .playOn, in: transition)
        }
        .popover(isPresented: showsPopover) {
            PlayOnSheet(isPopover: true)
        }
    }
}

/// The system AirPlay button: a tap puts up the system route sheet, the
/// same one Control Center shows, and the device's audio follows it.
private struct AirPlayRoutePicker: UIViewRepresentable {
    /// Draws the picker without its own glyph, for a symbol laid over it.
    var hidesGlyph = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // The glyph is drawn in these tints, so clear ones hide it while the
        // button still takes the tap.
        uiView.tintColor = hidesGlyph ? .clear : .label
        uiView.activeTintColor = hidesGlyph ? .clear : .tintColor
    }
}

struct PendingSwitch: Identifiable {
    let target: PlayDestination
    var id: String { target.groupID ?? "device" }
}

/// What a route switch asks: move what's playing along, or only change
/// where playback goes. Where it plays now and where it's going, each a
/// glyph and a name, over the question and its two answers. "Don't ask
/// again" writes the answer to the setting (Settings › Playback), so the
/// prompt is one tap to retire.
///
/// A sheet of its own height on the iPhone; on the iPad and the Mac a card
/// fitted to it (`presentationSizing(.fitted)`), as it opened as a large
/// panel there with the prompt lost in the middle of it.
struct RouteTransferPrompt: View {
    let target: PlayDestination
    let onChoose: (_ carrying: Bool) -> Void

    @State private var dontAskAgain = false
    @State private var height: CGFloat = 400

    private var route: PlaybackRoute { .shared }

    private var targetGroup: GroupRoom? {
        guard let id = target.groupID else { return nil }
        return SonosService.shared.groups.first { $0.coordinatorID == id }
    }

    private var sourceName: String {
        route.group?.nameWithCount ?? ThisDevice.name
    }

    private var targetName: String {
        guard target.groupID != nil else { return ThisDevice.name }
        return targetGroup?.nameWithCount ?? String(localized: "Speaker")
    }

    private static func symbol(for group: GroupRoom?) -> String {
        guard let group else { return ThisDevice.symbol }
        return group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill"
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 8) {
                RouteEnd(symbol: Self.symbol(for: route.group), name: sourceName, isTarget: false)
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: RouteEnd.side)
                RouteEnd(symbol: Self.symbol(for: target.groupID == nil ? nil : targetGroup), name: targetName, isTarget: true)
            }

            VStack(spacing: 6) {
                Text("Move What's Playing?")
                    .font(.title3.weight(.semibold))
                Text("Bring the queue from \(sourceName) to \(targetName), or switch and leave it playing where it is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    choose(carrying: true)
                } label: {
                    Text("Move to \(targetName)")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("Accent"))

                Button {
                    choose(carrying: false)
                } label: {
                    Text("Just Switch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                // Plain, not the accent: green on grey read poorly beside
                // the accent button.
                .tint(.primary)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)

            Toggle("Don't ask again", isOn: $dontAskAgain)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .tint(Color("Accent"))
        }
        .padding(24)
        .frame(maxWidth: 400)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationSizing(.fitted)
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

/// One end of a route switch: its glyph in a circle, the one it's going to
/// in the accent, over its name.
private struct RouteEnd: View {
    let symbol: String
    let name: String
    let isTarget: Bool

    static let side: CGFloat = 56

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isTarget ? AnyShapeStyle(Color("Accent")) : AnyShapeStyle(.primary))
                .frame(width: Self.side, height: Self.side)
                .background(isTarget ? AnyShapeStyle(Color("Accent").opacity(0.18)) : AnyShapeStyle(.quaternary), in: .circle)
            Text(name)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 120)
    }
}

#Preview {
    PlaybackRouteButton()
        .withEnvironments()
}
