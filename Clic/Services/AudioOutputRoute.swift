#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation

/// Where the device's own audio is going, and whether that means the phone's
/// volume and transport controls belong to something other than Clic.
enum AudioOutputRoute {
    /// True when audio is routed anywhere but the phone's own speaker or
    /// earpiece — Bluetooth, CarPlay, AirPlay, wired or wireless headphones.
    ///
    /// Two things are true on such a route and neither is true on the built-in
    /// one:
    ///
    /// - **The phone's volume is audible, and it isn't ours.** It's that
    ///   device's volume, and iOS remembers a separate level per route and
    ///   restores it on connect — a write that arrives as an ordinary
    ///   `outputVolume` change, indistinguishable from a button press.
    /// - **The device can issue transport commands.** A head unit's play
    ///   button, an inline remote, an AirPods stem press, a Shortcuts
    ///   automation that fires on connect: they all go to whichever app owns
    ///   Now Playing.
    ///
    /// Clic owning either of those while the user is somewhere else is the
    /// failure this exists to prevent. Reported from the beta: an automation
    /// that set the volume to 100% and pressed play when the phone connected to
    /// a car did both to a Sonos group at home, and left a pair of Fives
    /// blasting at full volume for the rest of the day. Clic was the Now
    /// Playing app, so it got the play command; the volume bridge was live, so
    /// it got the 100%.
    ///
    /// No outputs at all — an inactive session — reads as built-in. The
    /// conservative answer is the one that lets the feature run; the caller
    /// re-asks on every route change, and a route we can't see isn't one that
    /// can take a command from us either.
    static var isExternal: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .builtInSpeaker, .builtInReceiver:
                return false
            default:
                return true
            }
        }
    }
}
#endif
