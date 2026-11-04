import Defaults
import Foundation
import OSLog
import SonosKit
import UIKit

extension BookShelfWidgetState.Destination {
    /// This device, while Play goes to it, as the shelf widgets name it:
    /// what it plays through (the AirPods, the car, an AirPlay receiver), as
    /// the player names it under Play On, else the device ("iPhone"). Nil
    /// while the route points at a speaker, which they name instead.
    @MainActor
    static var thisDevice: Self? {
        guard PlaybackRoute.shared.destination == .device else { return nil }
        let output = AudioOutputName.shared
        return Self(name: output.name ?? UIDevice.current.model, symbol: output.symbol ?? AudioOutputName.deviceSymbol)
    }
}

/// A shelf widget's Play that would start something new with nothing
/// playing asks where first, in a list of where Cue can play: this device
/// and each speaker. Started where the route last pointed, a tap from the
/// Home Screen sent an album to a speaker in another room, or to the phone
/// with the speakers a tap away, with nothing on screen to say which.
///
/// The system's own list and interactive snippets can't show from a widget's
/// button: `chronod`, which runs the button's intent, answers `requestChoice`
/// with a cancel within milliseconds and never draws a snippet, whatever the
/// intent (iOS 27.2). So Cue comes to the front to
/// ask (iOS 26: `continueInForeground` from the intent, `bringForward`), and
/// asks in an action sheet over whatever is on screen. Where Cue can't come
/// forward, or there's one place to play, the Play goes where the route
/// points, as before. A tap on what's loaded plays or pauses it as before.
@MainActor
enum WidgetPlayChoice {
    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "widgets"' --level debug`
    private static let log = Logger(subsystem: "dance.cue", category: "widgets")

    enum Answer {
        /// Nothing asked: the Play goes where the route points.
        case notAsked
        /// A place chosen, and the route pointed there.
        case chosen
        /// Put away without a choice: nothing plays.
        case cancelled
    }

    /// Asks where `item` should play when nothing is playing where the
    /// route points and there's more than one place, once `bringForward` has
    /// brought Cue to the front (true once it's there), and points the route
    /// at the answer.
    static func ask(about item: PlayableContent, bringForward: @MainActor () async -> Bool) async -> Answer {
        // A file on this device plays here whatever is chosen.
        guard !item.content.service.playsOnDeviceOnly else { return .notAsked }
        await loadSpeakers()
        let places = choices()
        guard places.count > 1 else { return .notAsked }
        guard await !isPlayingWhereRoutePoints() else { return .notAsked }
        guard await bringForward() else {
            log.notice("widget play: nothing playing, but Cue can't come forward to ask; playing where the route points")
            return .notAsked
        }
        guard let presenter = await topControllerWhenReady() else {
            log.error("widget play: Cue came forward with no window to ask in; playing where the route points")
            return .notAsked
        }
        guard let destination = await choose(among: places, title: item.title, on: presenter) else {
            log.notice("widget play: where to play put away, nothing played")
            return .cancelled
        }
        let route = PlaybackRoute.shared
        if destination != route.destination {
            // Nothing is playing to carry.
            route.switchTo(destination, carrying: false)
        }
        log.notice("widget play: chose \(destination.groupID ?? "this device", privacy: .public)")
        return .chosen
    }

    // MARK: - Where

    private struct Place {
        let title: String
        let destination: PlayDestination
    }

    /// This device, then each speaker group it may play to (without Super,
    /// the free one), by the speaker list's order.
    private static func choices() -> [Place] {
        var places: [Place] = []
        if FeatureGate.shared.isAvailable(.onDevicePlayback) {
            let model = UIDevice.current.model
            let title = AudioOutputName.shared.name.map { "This \(model) · \($0)" } ?? "This \(model)"
            places.append(Place(title: title, destination: .device))
        }
        let sonos = SonosService.shared
        guard sonos.isAvailable else { return places }
        for group in sonos.sorted where group.isActive && FeatureGate.shared.isGroupUnlocked(group.coordinatorID) {
            places.append(Place(title: group.nameWithCount, destination: .group(group.coordinatorID)))
        }
        return places
    }

    /// Whether the route's end is playing: this device's player, or the
    /// speaker as it says itself, since a launch in the background for a
    /// widget's Play hasn't polled it. A hand-off under way counts.
    private static func isPlayingWhereRoutePoints() async -> Bool {
        let route = PlaybackRoute.shared
        if route.isHolding { return true }
        guard let group = route.group else {
            return LocalPlaybackService.shared.isPlaying
        }
        switch await SonosService.shared.getPlaybackInfo(ip: group.ip) {
        case .playing, .transitioning: return true
        case .paused: return false
        case .unknown: return group.coordinatorRoom.isPlaying
        }
    }

    /// The speakers, when none are loaded yet (a launch in the background
    /// for this Play), 3 s at most: there's no asking without them.
    private static func loadSpeakers() async {
        let sonos = SonosService.shared
        guard sonos.isAvailable, sonos.groups.isEmpty else { return }
        await PlayDestinationRouter.loadSpeakersIfNeeded()
        guard sonos.groups.isEmpty else { return }
        Task { try? await sonos.updateGroups() }
        for _ in 0..<12 where sonos.groups.isEmpty && sonos.isAvailable {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Asking

    /// The list, as an action sheet over whatever is on screen. Nil when
    /// it's put away, or taken down by something else.
    private static func choose(among places: [Place], title: String, on presenter: UIViewController) async -> PlayDestination? {
        await withCheckedContinuation { continuation in
            let answer = OnceAnswer(continuation)
            let sheet = UIAlertController(title: "Play “\(title)”", message: "Nothing is playing. Where should it play?", preferredStyle: .actionSheet)
            for place in places {
                sheet.addAction(UIAlertAction(title: place.title, style: .default) { _ in
                    answer.give(place.destination)
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                answer.give(nil)
            })
            // iPad's sheet is a popover; from the middle of the window, with
            // no arrow, as nothing on screen opened it.
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(sheet, animated: true)
            // A sheet taken down without a choice (something presented over
            // it, Cue sent away) gives no answer of its own.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                while !answer.isGiven {
                    if sheet.presentingViewController == nil {
                        answer.give(nil)
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    /// The top controller once Cue is in front with a window, 3 s at most:
    /// brought forward from the background, its scene is still coming up.
    /// Asked again a moment after it first looks ready, as Quick Launch
    /// opens the player as Cue comes to the front, and the sheet goes over
    /// the player rather than in its way.
    private static func topControllerWhenReady() async -> UIViewController? {
        func ready() -> UIViewController? {
            guard UIApplication.shared.applicationState == .active, let top = TopViewController.current,
                  top.viewIfLoaded?.window != nil, top.transitionCoordinator == nil else { return nil }
            return top
        }
        for _ in 0..<30 {
            if ready() != nil {
                try? await Task.sleep(for: .milliseconds(300))
                if let top = ready() { return top }
                continue
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// The sheet's answer, given once, whichever way it comes.
    @MainActor
    private final class OnceAnswer {
        private var continuation: CheckedContinuation<PlayDestination?, Never>?

        init(_ continuation: CheckedContinuation<PlayDestination?, Never>) {
            self.continuation = continuation
        }

        var isGiven: Bool { continuation == nil }

        func give(_ destination: PlayDestination?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: destination)
        }
    }
}
