import AVFoundation
import MediaToolbox

/// Copies what an `AVPlayerItem` plays, as it plays it, and hands each chunk
/// to `onBuffer` — the ear Live Transcription listens through.
///
/// An `MTAudioProcessingTap` on the item's audio track, pre-effects so the
/// player's volume (and mute) don't change what the transcriber hears. The
/// audio passes through untouched; the tap only reads it.
///
/// Only what `AVQueuePlayer` plays can be tapped: files and progressive
/// streams (Plex, Subsonic, Files, most TuneIn stations). An HLS station has
/// no track to tap, and Apple Music plays in the system's music service,
/// out of the app's reach entirely.
enum TranscriptionAudioTap {
    /// Installs the tap on `item`. Waits for the item to know its tracks
    /// (a stream only does once it's ready), and gives up if it never does.
    /// Returns whether a tap went on.
    @MainActor
    static func install(on item: AVPlayerItem, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async -> Bool {
        guard let track = await audioTrack(of: item) else { return false }

        let context = Unmanaged.passRetained(TapContext(onBuffer: onBuffer)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, description in
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.format = AVAudioFormat(streamDescription: description)
            },
            unprepare: { tap in
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.format = nil
            },
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.deliver(bufferList, frames: framesOut.pointee)
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr, let tap else {
            // `finalize` never runs for a tap that wasn't made.
            Unmanaged<TapContext>.fromOpaque(context).release()
            return false
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
        return true
    }

    /// Takes the tap back off, leaving the item as it was armed.
    @MainActor
    static func remove(from item: AVPlayerItem) {
        item.audioMix = nil
    }

    /// The item's audio track. A stream's asset only knows its tracks once
    /// the item is ready to play, so this waits — up to `timeout` — for that.
    @MainActor
    private static func audioTrack(of item: AVPlayerItem, timeout: Duration = .seconds(15)) async -> AVAssetTrack? {
        let deadline = ContinuousClock.now + timeout
        while item.status != .readyToPlay {
            guard item.status != .failed, ContinuousClock.now < deadline, !Task.isCancelled else { return nil }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let track = item.tracks.compactMap(\.assetTrack).first(where: { $0.mediaType == .audio }) {
            return track
        }
        return try? await item.asset.loadTracks(withMediaType: .audio).first
    }
}

/// What the tap's C callbacks reach through their storage pointer: the
/// format `prepare` announced, and where copies go.
private final class TapContext: @unchecked Sendable {
    let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    /// Set and read on the render thread only (`prepare` / `process`).
    var format: AVAudioFormat?

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    /// Copies the chunk the player is about to play into a buffer of our own;
    /// the player's goes on to the speaker unchanged.
    func deliver(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
        guard frames > 0, let format,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        copy.frameLength = AVAudioFrameCount(frames)
        let source = UnsafeMutableAudioBufferListPointer(bufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        onBuffer(copy)
    }
}
