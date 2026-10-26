import AVFoundation
import Defaults
import OSLog
import SonosKit
import SwiftUI
import UIKit

/// Apple Music's moving cover over a still one, where the album has one
/// (`MotionArtworkService`). Put in the still's own frame as an overlay, so
/// it's clipped, badged and dragged with it; it fades in once its first
/// frame is up, the still showing until then and wherever there's no video,
/// and it takes no touches.
///
/// A new song on the album already playing keeps the video going, its album
/// known from the song before (`MotionArtworkService.known(for:)`); a song
/// on another album drops it at once, before its own lookup, so a video
/// never plays over another album's cover.
struct MotionArtworkOverlay: View {
    let content: PlayableContent?
    /// The 3:4 video first, for a frame taller than it is wide.
    var prefersTall = false
    /// Holds the frame showing: the player's, while the music is paused.
    var isPaused = false

    @AppStorage(AppStorageKeys.videoCovers) private var preference: VideoCoverPreference = .defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The last lookup's answer and the item it was for.
    @State private var found: Found?
    @State private var isReady = false

    private struct Found: Equatable {
        let key: String
        let video: URL?
    }

    private var service: MotionArtworkService { .shared }

    private var key: String? {
        content.flatMap { MotionArtworkService.lookupKey(for: $0) }
    }

    private var isAllowed: Bool {
        !reduceMotion && service.allowsVideo(preference)
    }

    private var video: URL? {
        guard isAllowed, let content, let key else { return nil }
        if let found, found.key == key { return found.video }
        if case .video(let artwork) = service.known(for: content) {
            return artwork.video(tall: prefersTall)
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let video {
                LoopingVideoView(url: video, isPlaying: !isPaused && scenePhase == .active, isReady: $isReady)
                    .id(video)
                    .opacity(isReady ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isReady)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: video) {
            isReady = false
        }
        .task(id: isAllowed ? key : nil) {
            guard isAllowed, let content, let key else { return }
            let artwork = await service.artwork(for: content)
            guard !Task.isCancelled else { return }
            found = Found(key: key, video: artwork?.video(tall: prefersTall))
        }
    }
}

/// A muted video looping in an `AVPlayerLayer`, filling its frame (cropped,
/// as a still drawn `.fill` is). One a video: a new one is a new view.
private struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    @Binding var isReady: Bool

    func makeUIView(context: Context) -> LoopingVideoPlayerView {
        let view = LoopingVideoPlayerView(url: url)
        update(view)
        return view
    }

    func updateUIView(_ view: LoopingVideoPlayerView, context: Context) {
        update(view)
    }

    private func update(_ view: LoopingVideoPlayerView) {
        let isReady = $isReady
        view.onReadyChange = { isReady.wrappedValue = $0 }
        view.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: LoopingVideoPlayerView, coordinator: ()) {
        view.stop()
    }
}

/// The player behind `LoopingVideoView`. Plays only while it's in a window
/// and asked to, and pauses with Cue in the background.
///
/// Muted, with no AirPlay and nothing keeping the screen awake, so the only
/// thing it adds is the picture. A player in Cue's process may still take
/// Cue's audio session as it starts, which while Apple Music plays would
/// stop MusicKit's player (see `KeepAwakeAudio`): the first frame logs
/// whether other audio was playing before it started and two seconds after,
/// under `motionartwork`.
final class LoopingVideoPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var onReadyChange: ((Bool) -> Void)?

    private let url: URL
    private let name: String
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    /// Loops by seeking back, once the looper has failed.
    private var endObserver: NSObjectProtocol?
    private var isStopped = false
    private var wantsPlaying = false
    private var hasShown = false
    /// Whether other audio was playing as the video first started.
    private var otherAudioBeforeStart: Bool?

    private static let log = Logger(subsystem: "dance.cue", category: "motionartwork")

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(url: URL) {
        self.url = url
        name = url.lastPathComponent
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        let looper = AVPlayerLooper(player: player, templateItem: Self.item(url))
        self.looper = looper
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
        observations = [
            playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async { self?.readyChanged(ready) }
            },
            looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                let reason = looper.error?.localizedDescription ?? "no reason given"
                DispatchQueue.main.async { self?.failed(reason) }
            },
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func item(_ url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        // No more than a cover shows: the stream goes up to 4K.
        item.preferredMaximumResolution = CGSize(width: 1200, height: 1600)
        return item
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        updatePlayback()
    }

    /// Lets the player go, for good.
    func stop() {
        isStopped = true
        onReadyChange = nil
        observations.forEach { $0.invalidate() }
        observations = []
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        playerLayer.player = nil
    }

    private func updatePlayback() {
        guard !isStopped else { return }
        if wantsPlaying, window != nil {
            if otherAudioBeforeStart == nil {
                otherAudioBeforeStart = AVAudioSession.sharedInstance().isOtherAudioPlaying
            }
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 {
            player.pause()
        }
    }

    private func readyChanged(_ ready: Bool) {
        onReadyChange?(ready)
        guard ready, !hasShown else { return }
        hasShown = true
        let name = self.name
        let before = otherAudioBeforeStart
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let after = AVAudioSession.sharedInstance().isOtherAudioPlaying
            if before == true, !after {
                Self.log.error("video cover \(name, privacy: .public) showing; other audio was playing before it started and isn't now")
            } else {
                Self.log.info("video cover \(name, privacy: .public) showing; other audio before \(before ?? false), after \(after)")
            }
        }
    }

    /// The looper gave up, which it can on a stream: one item instead,
    /// sought back to its start at its end, with a moment's stall there.
    private func failed(_ reason: String) {
        guard !isStopped, endObserver == nil else { return }
        Self.log.error("video cover \(self.name, privacy: .public) can't loop (\(reason, privacy: .public)); seeking back instead")
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        let item = Self.item(url)
        player.actionAtItemEnd = .none
        player.insert(item, after: nil)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.player.seek(to: .zero)
            }
        }
        updatePlayback()
    }
}
