import AVFoundation
import Foundation
import OSLog
import SonosKit
#if canImport(Player) && canImport(Auth) && canImport(EventProducer)
import Auth
import EventProducer
import Player
#endif

/// TIDAL's own player (the Player module of `tidal-sdk-ios`), which is the
/// only way TIDAL lets an app play its audio: it fetches the stream for the
/// signed-in account (`TidalAccount`), plays it through `AVPlayer`, and
/// reports each play to TIDAL, which is how artists get paid.
///
/// The player holds one song and the song after it (`setNext`), and joins
/// the two without a gap. `LocalPlaybackService` runs a stretch of TIDAL
/// rows through it the way it runs a stream run through `AVQueuePlayer`, one
/// song ahead; each song carries its queue row's reference, so what's
/// playing can be read back as a row.
///
/// A thin wrapper so the SDK's names (`Player`, `State`, `Configuration`)
/// stay out of the rest of the app, where SwiftUI has its own `State`. The
/// SDK is linked into the iOS and Mac apps only; elsewhere this plays
/// nothing and `isAvailable` is false.
@MainActor
final class TidalPlayer {
    static let shared = TidalPlayer()

    /// What the player says happened, on the main actor.
    enum Event {
        /// The song with this reference played to its end. The player goes
        /// on to the next one, if one was set.
        case ended(reference: String?)
        /// The current song couldn't play; the player has stopped. `skips`
        /// when it's the song (not where it's played, say), so the next one
        /// may well play; otherwise the next would fail the same way.
        case failed(message: String, skips: Bool)
        /// The account started playing on another device, and the player
        /// paused for it: TIDAL plays on one device at a time.
        case playingElsewhere
    }

    /// Where the player is, read off it each poll.
    struct Status {
        /// The playing song's reference, or nil with nothing loaded.
        var reference: String?
        var isPlaying = false
        /// Nothing loaded: never started, reset, or past the last song.
        var isIdle = true
        /// Seconds into the song: zero until it has loaded.
        var position: TimeInterval?
        /// The length of what plays, which for a preview is the preview's.
        /// Nil until the song has loaded.
        var duration: TimeInterval?
        /// Whether the song has loaded, so a seek lands in it.
        var isLoaded: Bool { reference != nil && duration != nil }
        var quality: SonosTrackQuality?
        /// Why the song is a 30-second preview rather than the whole song,
        /// or nil when it plays in full (or hasn't loaded yet).
        var previewNotice: String?
    }

    /// Called for each `Event`. Set by `LocalPlaybackService`.
    var onEvent: (@MainActor (Event) -> Void)?

    static var isAvailable: Bool { TidalAccount.isAvailable }

    nonisolated private static let log = Logger(subsystem: "dance.cue", category: "tidal")

    #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
    private lazy var listener = Listener { [weak self] event in
        self?.onEvent?(event)
    }

    /// The SDK's player, once the first play has started it.
    private var player: Player?

    /// `player`, bootstrapping it if this is the first play. Not done at
    /// launch: it opens a database and network monitors, which nobody who
    /// never plays TIDAL needs. `Player.bootstrap` answers once per process,
    /// so the instance is kept.
    private func startedPlayer() -> Player? {
        if let player { return player }
        TidalAccount.shared.configure()
        guard Self.isAvailable else { return nil }
        let started = Player.bootstrap(
            playerListener: listener,
            credentialsProvider: TidalAuth.shared,
            eventSender: TidalEventSender.shared
        )
        // The default for cellular is TIDAL's lowest, 96 kbps AAC.
        started?.configuration.streamingCellularAudioQuality = .HIGH
        if started == nil {
            Self.log.error("TIDAL's player didn't start")
        }
        player = started
        return started
    }
    #endif

    private init() {}

    /// Loads `trackID` and plays it, dropping whatever was loaded.
    /// `reference` identifies the queue row it plays for.
    func play(trackID: String, reference: String) {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        guard let player = startedPlayer() else {
            // Later, as the player's own events come: the caller is still
            // setting the run up.
            Task { @MainActor [weak self] in
                self?.onEvent?(.failed(message: "Tidal can’t play on this device right now.", skips: false))
            }
            return
        }
        player.load(Self.product(trackID: trackID, reference: reference))
        player.play()
        #endif
    }

    /// The song to join on to the current one when it ends, or nil for
    /// none: the player then stops after the current song.
    func setNext(trackID: String?, reference: String?) {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        guard let player else { return }
        if let trackID, let reference {
            player.setNext(Self.product(trackID: trackID, reference: reference))
        } else {
            player.setNext(nil)
        }
        #endif
    }

    /// Moves straight on to the song set as next.
    func skipToNext() {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        player?.skipToNext()
        #endif
    }

    func resume() {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        player?.play()
        #endif
    }

    func pause() {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        player?.pause()
        #endif
    }

    func seek(to seconds: TimeInterval) {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        player?.seek(seconds)
        #endif
    }

    /// Stops and unloads everything.
    func reset() {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        player?.reset()
        #endif
    }

    var status: Status {
        #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
        guard let player else { return Status() }
        var status = Status()
        let state = player.getState()
        // Stalled is waiting for the network, still meaning to play.
        status.isPlaying = state == .PLAYING || state == .STALLED
        status.isIdle = state == .IDLE
        status.reference = player.getActiveMediaProduct()?.referenceId
        status.position = player.getAssetPosition()
        if let context = player.getActivePlaybackContext() {
            status.duration = context.duration > 0 ? context.duration : nil
            status.quality = Self.quality(of: context)
            if context.assetPresentation == .PREVIEW {
                status.previewNotice = Self.previewNotice(for: context.previewReason)
            }
        }
        return status
        #else
        return Status()
        #endif
    }

    #if canImport(Player) && canImport(Auth) && canImport(EventProducer)
    nonisolated private static func product(trackID: String, reference: String) -> MediaProduct {
        MediaProduct(
            productType: .TRACK,
            productId: trackID,
            referenceId: reference,
            progressSource: nil,
            playLogSource: nil,
            extras: nil
        )
    }

    /// The Sonos-shaped quality for what the player is decoding. Nothing
    /// for plain lossy stereo — there is nothing to badge.
    nonisolated private static func quality(of context: PlaybackContext) -> SonosTrackQuality? {
        if context.audioMode == .DOLBY_ATMOS || context.audioMode == .SONY_360RA {
            return SonosTrackQuality(lossless: false, immersive: true)
        }
        switch context.audioQuality {
        case .LOSSLESS, .HI_RES, .HI_RES_LOSSLESS:
            return SonosTrackQuality(
                bitDepth: context.audioBitDepth,
                lossless: true,
                immersive: false,
                sampleRate: context.audioSampleRate
            )
        default:
            return nil
        }
    }

    nonisolated private static func previewNotice(for reason: PreviewReason?) -> String {
        switch reason {
        case .FULL_REQUIRES_SUBSCRIPTION:
            "Tidal is playing 30-second previews: your Tidal account needs a subscription for full songs."
        case .FULL_REQUIRES_PURCHASE:
            "Tidal is playing a 30-second preview: this song has to be bought on Tidal to play in full."
        case .FULL_REQUIRES_HIGHER_ACCESS_TIER, nil:
            "Tidal is playing 30-second previews in Cue until Tidal approves it for full songs."
        }
    }

    nonisolated private static func message(for error: PlayerError) -> String {
        switch error.errorId {
        case .PEContentNotAvailableInLocation:
            "This song isn’t available on Tidal where you are."
        case .PEContentNotAvailableForSubscription:
            "Your Tidal subscription doesn’t include this song."
        case .PEMonthlyStreamQuotaExceeded:
            "Your Tidal account has reached its streaming limit for the month."
        case .PENetwork, .PERetryable:
            "Couldn’t reach Tidal. Check your connection."
        case .PENotAllowedInOfflineMode:
            "Tidal can’t play while Cue is offline."
        default:
            "Tidal couldn’t play this song (\(error.errorCode))."
        }
    }

    /// The SDK's listener. Not on the main actor itself, though the SDK
    /// calls it on the main queue (`listenerQueue`'s default), so each call
    /// hops over without waiting.
    private final class Listener: PlayerListener {
        private let send: @MainActor (Event) -> Void

        init(send: @escaping @MainActor (Event) -> Void) {
            self.send = send
        }

        func stateChanged(to state: State) {}

        func ended(_ mediaProduct: MediaProduct) {
            let reference = mediaProduct.referenceId
            deliver(.ended(reference: reference))
        }

        func mediaTransitioned(to mediaProduct: MediaProduct, with playbackContext: PlaybackContext) {}

        func failed(with error: PlayerError) {
            TidalPlayer.log.error("TIDAL playback failed: \(error.errorId.rawValue, privacy: .public) \(error.errorCode, privacy: .public)")
            let skips = [ErrorId.PEContentNotAvailableInLocation, .PEContentNotAvailableForSubscription].contains(error.errorId)
            deliver(.failed(message: TidalPlayer.message(for: error), skips: skips))
        }

        func streamingPrivilegesLost(to device: String?) {
            deliver(.playingElsewhere)
        }

        func mediaServicesWereReset() {
            // The audio session's setup is gone with the media services.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        private func deliver(_ event: Event) {
            let send = send
            Task { @MainActor in send(event) }
        }
    }
    #endif
}
