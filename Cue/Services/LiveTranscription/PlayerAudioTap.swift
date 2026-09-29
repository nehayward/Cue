import Accelerate
import AVFoundation
import MediaToolbox
import OSLog

/// Listens in on an `AVPlayerItem`'s own audio as it plays: an
/// `MTAudioProcessingTap` on the item's whole mix, the
/// `AVAudioMixInputParametersTrackID.mixID` input new in iOS 27. Before it, a
/// tap needed an asset track, which a live Icecast or HLS stream never has.
///
/// Each chunk comes with where it sits on the item's timeline, so words the
/// model hears can be lined up with the player's clock. The tap sees audio
/// before it's heard — well before, on AirPlay, which buffers ahead — so a
/// transcript built from it can be shown in step with the station.
///
/// The mix reaches the tap after the player's volume, so a player at zero
/// hands it silence. The player is kept at full level while tapped instead,
/// and the tap applies the volume itself (`TapGain`) after taking its copy:
/// what's heard is unchanged, and the transcript keeps going with the volume
/// down. FairPlay-protected audio never reaches it.
///
/// The mix behind the tap renders at most 1024 frames at a time. Once the
/// system asks for more — 4096 at a time, when the app isn't frontmost — it
/// fails every render ("MESubmixGraph err -10874") and hands back silence,
/// and it can't be asked in slices: a second pull in one render crashes.
/// The tap says so once (`onUnusable`) so its owner can take it off.
@available(iOS 27.0, visionOS 27.0, *)
enum PlayerAudioTap {
    /// A chunk of the item's audio and where it starts on the item's timeline.
    typealias Handler = @Sendable (AVAudioPCMBuffer, CMTime) -> Void

    /// An audio mix that hands every chunk the item plays to `onAudio`, on
    /// the render thread, then plays it at `gain`. `onUnusable` is called
    /// once, on the render thread, if the item's renders outgrow the tap.
    /// Nil if the tap couldn't be made.
    static func audioMix(gain: TapGain, onAudio: @escaping Handler, onUnusable: @escaping @Sendable () -> Void) -> AVAudioMix? {
        let context = Unmanaged.passRetained(TapContext(gain: gain, onAudio: onAudio, onUnusable: onUnusable)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: { _, clientInfo, storage in
                storage.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                TapContext.from(tap).prepare(format)
                Logger.liveTranscription.info("Tap prepared: \(TapContext.from(tap).format?.description ?? "no format", privacy: .public), up to \(maxFrames) frames")
            },
            unprepare: { tap in
                TapContext.from(tap).unprepare()
            },
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                TapContext.from(tap).process(tap, frames: frames, bufferList: bufferList, framesOut: framesOut, flagsOut: flagsOut)
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr, let tap else {
            // The finalize callback never runs for a tap that wasn't made.
            Unmanaged<TapContext>.fromOpaque(context).release()
            return nil
        }

        let parameters = AVMutableAudioMixInputParameters()
        parameters.trackID = AVAudioMixInputParametersTrackID.mixID.rawValue
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}

/// The level a tapped item plays at, 0...1 — the player's volume, applied by
/// the tap because the player itself is kept at full level for it. Written
/// from the main thread, read on the render thread; a lone aligned `Float`
/// is read and written whole, so a stale read costs one chunk at the old
/// level at most.
final class TapGain: @unchecked Sendable {
    var value: Float = 1
}

/// The tap's state, owned by the tap: made with it, released in its
/// finalize. Only touched from the tap's own callbacks.
private final class TapContext: @unchecked Sendable {
    let gain: TapGain
    let onAudio: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    let onUnusable: @Sendable () -> Void
    private(set) var format: AVAudioFormat?
    /// Whether `onUnusable` has been called.
    private var isUnusable = false

    /// The most the item's mix renders in one pull; see `PlayerAudioTap`.
    private static let maxFrames = 1024
    /// How long renders may run oversized before the tap gives up. A single
    /// long render comes as a tap attaches to a playing item and the ones
    /// after it are small again; it's a run of them — the app gone to the
    /// background — that means silence from here on.
    private static let oversizedGrace: Double = 2
    /// Seconds of oversized renders in a row.
    private var oversizedRun: Double = 0

    /// Pulls that failed, for the log.
    private var failures = 0

    init(gain: TapGain, onAudio: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void, onUnusable: @escaping @Sendable () -> Void) {
        self.gain = gain
        self.onAudio = onAudio
        self.onUnusable = onUnusable
    }

    static func from(_ tap: MTAudioProcessingTap) -> TapContext {
        Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    func prepare(_ description: UnsafePointer<AudioStreamBasicDescription>) {
        format = AVAudioFormat(streamDescription: description)
    }

    func unprepare() {
        format = nil
    }

    func process(
        _ tap: MTAudioProcessingTap,
        frames: CMItemCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        framesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        if frames > Self.maxFrames {
            oversizedRun += Double(frames) / (format?.sampleRate ?? 48_000)
            if oversizedRun > Self.oversizedGrace, !isUnusable {
                isUnusable = true
                print("Live Transcription: Tap asked for \(frames) frames at a time for \(oversizedRun)s, more than it can render")
                onUnusable()
            }
        } else {
            oversizedRun = 0
        }
        var timeRange = CMTimeRange.zero
        let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, &timeRange, framesOut)
        guard status == noErr else {
            noteFailure(status, frames: frames)
            return
        }
        deliver(bufferList, frames: framesOut.pointee, start: timeRange.start)
        applyGain(to: bufferList, frames: framesOut.pointee)
    }

    /// Copies the chunk out — the tap's buffers are only lent for the
    /// callback — and passes it on, before the volume is applied to it.
    private func deliver(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount, start: CMTime) {
        guard let format, frames > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        copy.frameLength = AVAudioFrameCount(frames)
        for (from, to) in zip(Self.buffers(in: bufferList), Self.buffers(in: copy.mutableAudioBufferList)) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        onAudio(copy, start)
    }

    /// Plays the chunk at the player's volume. The tap's format is Float32
    /// unless asked otherwise; anything else goes out at full level.
    private func applyGain(to bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
        var level = gain.value
        guard level != 1, format?.commonFormat == .pcmFormatFloat32 else { return }
        for buffer in Self.buffers(in: bufferList) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = min(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size, frames * Int(buffer.mNumberChannels))
            vDSP_vsmul(data, 1, &level, data, 1, vDSP_Length(count))
        }
    }

    private func noteFailure(_ status: OSStatus, frames: CMItemCount) {
        failures += 1
        if failures == 1 || failures % 100 == 0 {
            Logger.liveTranscription.error("Tap couldn't pull \(frames) frames: \(status) (\(self.failures) so far)")
        }
    }

    /// The list's buffers — `mBuffers` is declared as one, but the list holds
    /// `mNumberBuffers` of them back to back.
    private static func buffers(in list: UnsafeMutablePointer<AudioBufferList>) -> UnsafeMutableBufferPointer<AudioBuffer> {
        let offset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!
        let first = (UnsafeMutableRawPointer(list) + offset).assumingMemoryBound(to: AudioBuffer.self)
        return UnsafeMutableBufferPointer(start: first, count: Int(list.pointee.mNumberBuffers))
    }
}
