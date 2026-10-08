#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import SonosKit
import UIKit

/// Whether this iPhone is in a car, for `SonosService.isInCar`: a speaker
/// has no place there, so while it is, the phone's app acts as if Sonos
/// were off, as on cellular. The route reads This Device, speaker UI hides,
/// the Play On button is the AirPlay picker and nothing looks for speakers.
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

    /// CarPlay's scene connected or went.
    static func sceneConnected(_ connected: Bool) {
        hasScene = connected
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
#endif
