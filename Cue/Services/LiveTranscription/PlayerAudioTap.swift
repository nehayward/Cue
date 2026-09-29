import Accelerate
import AVFoundation
import MediaToolbox

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
@available(iOS 27.0, visionOS 27.0, *)
enum PlayerAudioTap {
    /// A chunk of the item's audio and where it starts on the item's timeline.
    typealias Handler = @Sendable (AVAudioPCMBuffer, CMTime) -> Void

    /// An audio mix that hands every chunk the item plays to `onAudio`, on
    /// the render thread, then plays it at `gain`. Nil if the tap couldn't be
    /// made.
    static func audioMix(gain: TapGain, onAudio: @escaping Handler) -> AVAudioMix? {
        let context = Unmanaged.passRetained(TapContext(gain: gain, onAudio: onAudio)).toOpaque()
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
                print("Live Transcription: Tap prepared: \(TapContext.from(tap).format?.description ?? "no format"), up to \(maxFrames) frames")
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
    private(set) var format: AVAudioFormat?
    /// Bytes per frame in each of the item's buffers.
    private var bytesPerFrame = 0
    /// A buffer list pointing into part of the one being filled, for pulling
    /// a long render in slices. Made in prepare, off the render thread.
    private var slice: UnsafeMutableRawPointer?

    /// The most the item's mix will render in one pull. It fails anything
    /// longer ("MESubmixGraph err -10874") and hands back silence — and the
    /// system asks for 4096 at a time once the app is in the background — so
    /// longer renders are pulled a slice at a time.
    private static let maxSlice = 1024

    /// For the log: chunks handed on and pulls that failed, and the audio's
    /// length when last logged.
    private var chunks = 0
    private var failures = 0
    private var framesSinceLog: Double = 0
    /// The loudest sample since last logged, 0...1 — near zero means the
    /// tap hears silence.
    private var peak: Float = 0

    init(gain: TapGain, onAudio: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) {
        self.gain = gain
        self.onAudio = onAudio
    }

    deinit {
        slice?.deallocate()
    }

    static func from(_ tap: MTAudioProcessingTap) -> TapContext {
        Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    func prepare(_ description: UnsafePointer<AudioStreamBasicDescription>) {
        format = AVAudioFormat(streamDescription: description)
        bytesPerFrame = Int(description.pointee.mBytesPerFrame)
        let isInterleaved = description.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let bufferCount = isInterleaved ? 1 : Int(description.pointee.mChannelsPerFrame)
        slice?.deallocate()
        slice = UnsafeMutableRawPointer.allocate(
            byteCount: Self.bufferListOffset + MemoryLayout<AudioBuffer>.stride * max(bufferCount, 1),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
    }

    func unprepare() {
        format = nil
        slice?.deallocate()
        slice = nil
    }

    func process(
        _ tap: MTAudioProcessingTap,
        frames: CMItemCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        framesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        var start = CMTime.invalid
        let status = pull(tap, frames: frames, into: bufferList, framesOut: framesOut, flagsOut: flagsOut, start: &start)
        guard status == noErr else {
            noteFailure(status, frames: frames)
            return
        }
        deliver(bufferList, frames: framesOut.pointee, start: start)
        applyGain(to: bufferList, frames: framesOut.pointee)
    }

    /// Fills `bufferList` from the item's mix, `maxSlice` frames at a time.
    /// `start` is where the first frame sits on the item's timeline.
    private func pull(
        _ tap: MTAudioProcessingTap,
        frames: CMItemCount,
        into bufferList: UnsafeMutablePointer<AudioBufferList>,
        framesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>,
        start: inout CMTime
    ) -> OSStatus {
        var timeRange = CMTimeRange.zero
        guard frames > Self.maxSlice, let slice, bytesPerFrame > 0 else {
            let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, &timeRange, framesOut)
            start = timeRange.start
            return status
        }

        let whole = Self.buffers(in: bufferList)
        let part = slice.bindMemory(to: AudioBufferList.self, capacity: 1)
        part.pointee.mNumberBuffers = UInt32(whole.count)
        let parts = Self.buffers(in: part)
        var done = 0
        var flags = MTAudioProcessingTapFlags()
        while done < Int(frames) {
            let wanted = min(Self.maxSlice, Int(frames) - done)
            for index in whole.indices {
                parts[index] = AudioBuffer(
                    mNumberChannels: whole[index].mNumberChannels,
                    mDataByteSize: UInt32(wanted * bytesPerFrame),
                    mData: whole[index].mData.map { $0 + done * bytesPerFrame }
                )
            }
            var got: CMItemCount = 0
            let status = MTAudioProcessingTapGetSourceAudio(tap, wanted, part, &flags, &timeRange, &got)
            guard status == noErr else { return status }
            if done == 0 {
                start = timeRange.start
                flagsOut.pointee = flags
            }
            done += got
            if got < wanted { break }
        }
        framesOut.pointee = done
        for index in whole.indices {
            whole[index].mDataByteSize = UInt32(done * bytesPerFrame)
        }
        return noErr
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

        if let channels = copy.floatChannelData {
            for channel in 0..<Int(copy.format.channelCount) {
                for frame in 0..<Int(copy.frameLength) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
        }
        chunks += 1
        framesSinceLog += Double(frames)
        if chunks == 1 || framesSinceLog >= format.sampleRate * 10 {
            framesSinceLog = 0
            print("Live Transcription: Tap chunk \(self.chunks): \(frames) frames at \(start.isNumeric ? start.seconds : -1)s, peak \(self.peak)")
            peak = 0
        }
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
            print("Live Transcription: Tap couldn't pull \(frames) frames: \(status) (\(self.failures) so far)")
        }
    }

    private static let bufferListOffset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!

    /// The list's buffers — `mBuffers` is declared as one, but the list holds
    /// `mNumberBuffers` of them back to back.
    private static func buffers(in list: UnsafeMutablePointer<AudioBufferList>) -> UnsafeMutableBufferPointer<AudioBuffer> {
        let first = (UnsafeMutableRawPointer(list) + bufferListOffset).assumingMemoryBound(to: AudioBuffer.self)
        return UnsafeMutableBufferPointer(start: first, count: Int(list.pointee.mNumberBuffers))
    }
}
