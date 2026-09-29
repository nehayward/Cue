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
/// It reads the audio before the player's volume, so it keeps hearing with
/// the volume down. FairPlay-protected audio never reaches it.
@available(iOS 27.0, visionOS 27.0, *)
enum PlayerAudioTap {
    /// A chunk of the item's audio and where it starts on the item's timeline.
    typealias Handler = @Sendable (AVAudioPCMBuffer, CMTime) -> Void

    /// An audio mix that hands every chunk the item plays to `onAudio`, on
    /// the render thread. Nil if the tap couldn't be made.
    static func audioMix(onAudio: @escaping Handler) -> AVAudioMix? {
        let context = Unmanaged.passRetained(TapContext(onAudio: onAudio)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: { _, clientInfo, storage in
                storage.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                TapContext.from(tap).format = AVAudioFormat(streamDescription: format)
            },
            unprepare: { tap in
                TapContext.from(tap).format = nil
            },
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                var timeRange = CMTimeRange.zero
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, &timeRange, framesOut)
                guard status == noErr else { return }
                TapContext.from(tap).deliver(bufferList, frames: framesOut.pointee, start: timeRange.start)
            }
        )

        var tap: MTAudioProcessingTap?
        // Pre-effects: the audio as decoded, before the player's volume.
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

/// The tap's state, owned by the tap: made with it, released in its
/// finalize. Only touched from the tap's own callbacks.
private final class TapContext: @unchecked Sendable {
    let onAudio: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    var format: AVAudioFormat?

    init(onAudio: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) {
        self.onAudio = onAudio
    }

    static func from(_ tap: MTAudioProcessingTap) -> TapContext {
        Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    /// Copies the chunk out — the tap's buffers are only lent for the
    /// callback — and passes it on. The audio itself goes on untouched.
    func deliver(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount, start: CMTime) {
        guard let format, frames > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        copy.frameLength = AVAudioFrameCount(frames)
        let source = UnsafeMutableAudioBufferListPointer(bufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        onAudio(copy, start)
    }
}
