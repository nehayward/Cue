#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import SonosKit
import UIKit

/// Whether this iPhone is in a car, for `SonosService.isInCar`: a speaker
/// has no place there, so while it is, the phone's app acts as if Sonos
/// were off, as on cellular. The route reads This Device, speaker UI hides,
/// the Play On button is the AirPlay picker and nothing looks for speakers.
/// CarPlay still looks for the speakers itself, and offers them when they
/// answer, as in a car parked at home; once one is picked there
/// (`CarSpeakerControl`) the car changes none of that.
///
/// In a car means CarPlay's screen is up (`CarPlaySceneDelegate`) or the
/// sound goes to CarPlay. Either alone misses a case: the car connects
/// Cue's scene only once Cue is opened on its screen, while the audio route
/// reads CarPlay as soon as the car is connected, with Cue playing from the
/// phone in a pocket or not playing at all. A Bluetooth car stereo without
/// CarPlay doesn't count; it's a route like headphones.
@MainActor
enum CarConnection {
    /// CarPlay's scene is connected.
    private static var hasScene = false
    /// The audio route ends in CarPlay.
    private static var routesToCar = false
    private static var observers: [NSObjectProtocol] = []

    /// Follows the audio route from here on. Called once at launch, before
    /// anything can look for speakers.
    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // The route again on the way back to the foreground: a change made
        // while Cue was suspended isn't delivered.
        for name in [AVAudioSession.routeChangeNotification, UIApplication.willEnterForegroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    readRoute()
                }
            })
        }
        readRoute()
    }

    /// CarPlay's scene connected or went. Going, the car lets go of a speaker
    /// it was driving (`CarSpeakerControl`).
    static func sceneConnected(_ connected: Bool) {
        hasScene = connected
        if !connected {
            CarSpeakerControl.shared.release()
        }
        update()
    }

    private static func readRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        routesToCar = outputs.contains { $0.portType == .carAudio }
        update()
    }

    private static func update() {
        SonosService.shared.setInCar(hasScene || routesToCar)
    }
}

/// Whether the car is driving a Sonos speaker: the speakers answered from
/// the car (the iPhone on the home Wi‑Fi, a car parked at home), and one was
/// picked in CarPlay since it connected: in its Play On, or Home's row for
/// the speaker the phone was last on. While it is, Sonos is available in the
/// car (`SonosService.carDrivesSpeaker`), the car's picks play on that
/// speaker (`CarPlayPlayback`) and the speaker's Now Playing card comes to
/// the car, so the car's screen and its buttons play, pause and skip it
/// (`NowPlayingSessionService`).
///
/// Only from a pick, never from the speakers answering alone: nothing tells
/// a car parked at home from one about to leave, and a speaker remembered
/// from the house would otherwise take an album picked for the drive, or
/// have its card, and the car's play button, take over the car's audio as
/// someone played it indoors. Picking This iPhone, a play on this iPhone
/// from the car, or the car going, lets go.
@MainActor
final class CarSpeakerControl {
    static let shared = CarSpeakerControl()

    private init() {}

    /// A speaker was picked from the car since it connected. Observable
    /// through `SonosService`, which keeps it.
    var isTaken: Bool {
        SonosService.shared.carDrivesSpeaker
    }

    /// The group the car drives: the route's, while taken and in reach. Nil
    /// plays here, and keeps the card off the car.
    var group: GroupRoom? {
        let sonos = SonosService.shared
        guard sonos.carDrivesSpeaker, sonos.isInCar, sonos.isAvailable else { return nil }
        return PlaybackRoute.shared.group
    }

    func take() {
        SonosService.shared.setCarDrivesSpeaker(true)
    }

    func release() {
        SonosService.shared.setCarDrivesSpeaker(false)
    }
}
#endif
