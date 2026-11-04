import AVFoundation
import SwiftUI

/// What this device's own audio plays through when that isn't the device
/// itself — "Nick's AirPods", the car, an AirPlay receiver, wired headphones
/// — for the player to name under its Play On button, the way Music names
/// them under its AirPlay button. Without it, This Device read the same on
/// the phone's speaker and in someone's ears, and the only way to tell
/// whether Bluetooth had connected was to press play and listen.
///
/// `nil` on the built-in speaker or earpiece, with no output at all (an
/// inactive session can report none), and on the Mac and Vision Pro, whose
/// outputs are the system's to show.
@MainActor
@Observable
final class AudioOutputName {
    static let shared = AudioOutputName()

    /// One output by its name, two as "A + B", more as "A + 2", the way a
    /// Sonos group reads on the same line.
    private(set) var name: String? = nil

    /// An SF Symbol for the first of them (AirPods, a car, AirPlay,
    /// headphones), nil with `name`. The shelf widgets draw it beside the
    /// name, as they draw a speaker beside a group's.
    private(set) var symbol: String? = nil

    /// The device itself, for where it plays with nothing external.
    static var deviceSymbol: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

#if os(iOS) && !targetEnvironment(macCatalyst)
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    private init() {
        name = Self.read()
        symbol = AudioOutputRoute.externalSymbol
        let center = NotificationCenter.default
        observers = [
            // AirPods connecting or put away, a car, AirPlay starting or
            // ending: each is a route change.
            Task { [weak self] in
                for await _ in center.notifications(named: AVAudioSession.routeChangeNotification) {
                    self?.update()
                }
            },
            // A change made while Cue was suspended isn't delivered.
            Task { [weak self] in
                for await _ in center.notifications(named: UIApplication.willEnterForegroundNotification) {
                    self?.update()
                }
            },
        ]
    }

    private func update() {
        let name = Self.read()
        let symbol = AudioOutputRoute.externalSymbol
        // `@Observable` notifies on every write, equal or not.
        if symbol != self.symbol {
            self.symbol = symbol
        }
        guard name != self.name else { return }
        self.name = name
    }

    private static func read() -> String? {
        let names = AudioOutputRoute.externalNames
        switch names.count {
        case 0:
            return nil
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) + \(names[1])"
        default:
            return "\(names[0]) + \(names.count - 1)"
        }
    }
#else
    private init() {}
#endif
}
