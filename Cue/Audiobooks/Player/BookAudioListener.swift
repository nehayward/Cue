import AVFoundation
import MediaToolbox
import MusicSearchKit
import os
import OSLog

/// Listens to a book's files as this device plays them and keeps how loud
/// the last half minute was (`LoudnessMeter`), so Smart Resume can start
/// again in a pause between words or sentences (`SpeechGaps`), not in a
/// word.
///
/// It's an audio tap on the player item (`MTAudioProcessingTap`): the
/// item's own audio passes through untouched, measured on the way, so a
/// file streamed from the server is heard as a downloaded one is, with
/// nothing fetched twice. A tap needs an audio track, which a book's file
/// has (it plays as the server keeps it); a live stream or HLS has none.
@MainActor
final class BookAudioListener {
    static let shared = BookAudioListener()

    private struct Entry {
        weak var item: AVPlayerItem?
        let meter: TapMeter
    }

    /// The items listened to, while they live.
    private var entries: [Entry] = []

    private init() {}

    /// Listens to `item`, one of a book's files, from when its audio track
    /// has loaded (which the player needs too, so it's no extra wait).
    func listen(to item: AVPlayerItem) {
        entries.removeAll { $0.item == nil }
        guard !entries.contains(where: { $0.item === item }) else { return }
        let meter = TapMeter()
        entries.append(Entry(item: item, meter: meter))
        let asset = item.asset
        Task { [weak item] in
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first, let item else { return }
            guard let tap = meter.makeTap() else {
                AudiobookPlayer.log.error("smart resume: no audio tap for a book file")
                return
            }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

    /// What was heard of `item` up to `offset` (where it paused), on the
    /// file's clock. Nil when nothing was, or when it doesn't end near
    /// there: the tap runs a moment ahead of what's heard, but more than
    /// that and its clock isn't the player's.
    func heard(_ item: AVPlayerItem, upTo offset: TimeInterval) -> LoudnessTrace? {
        guard let meter = entries.first(where: { $0.item === item })?.meter else { return nil }
        let (trace, isAnchored) = meter.snapshot()
        guard let end = trace.end else { return nil }
        let heard = isAnchored ? trace : trace.shifted(by: offset - end)
        guard let heardEnd = heard.end, abs(heardEnd - offset) <= 1.5 else {
            AudiobookPlayer.log.notice("smart resume: what was heard ends at \(Int(end)) s, not near the pause at \(Int(offset)) s; not used")
            return nil
        }
        return heard
    }
}

/// The meter a tap writes on the audio thread and Smart Resume reads on the
/// main one, behind a lock that's only ever held for a moment.
private final class TapMeter {
    private var meter = LoudnessMeter()
    private var format = AudioStreamBasicDescription()
    /// Each frame's energy, summed over the channels, for one block.
    private var energies: UnsafeMutablePointer<Float>?
    private var energyCapacity = 0
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        energies?.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// The trace so far, copied here so the audio thread never has to copy
    /// it (an allocation) the next time it writes.
    func snapshot() -> (LoudnessTrace, Bool) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let times = meter.trace.times.map { $0 }
        let levels = meter.trace.levels.map { $0 }
        return (LoudnessTrace(times: times, levels: levels, windowLength: meter.trace.windowLength), meter.isAnchored)
    }

    /// A tap that measures into this meter. It holds the meter until the
    /// tap goes with its item.
    func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: { _, clientInfo, storage in
                storage.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                TapMeter.of(tap).prepare(maxFrames: Int(maxFrames), format: format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, flags, buffers, framesOut, flagsOut in
                // Passed on as it is; only measured.
                var timeRange = CMTimeRange.invalid
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, &timeRange, framesOut) == 0 else { return }
                let restarted = (flags | flagsOut.pointee) & kMTAudioProcessingTapFlag_StartOfStream != 0
                TapMeter.of(tap).measure(buffers, frames: Int(framesOut.pointee), timeRange: timeRange, restarted: restarted)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        // On a failure the retain above may never be given back: a leak of
        // one small object, which beats releasing it twice.
        guard status == 0 else { return nil }
        return tap
    }

    private static func of(_ tap: MTAudioProcessingTap) -> TapMeter {
        Unmanaged<TapMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    private func prepare(maxFrames: Int, format: AudioStreamBasicDescription) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        self.format = format
        if maxFrames > energyCapacity {
            energies?.deallocate()
            energyCapacity = max(maxFrames, 4096)
            energies = .allocate(capacity: energyCapacity)
        }
        meter.reset()
    }

    private func measure(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, timeRange: CMTimeRange, restarted: Bool) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let rate = format.mSampleRate
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard frames > 0, rate > 0, let energies,
              isFloat ? format.mBitsPerChannel == 32 : format.mBitsPerChannel == 16 else { return }
        let count = min(frames, energyCapacity)
        if restarted { meter.reset() }
        // The block's place in the file, and how much of the file a frame
        // is: more than a sample's length when played faster.
        let isTimed = timeRange.isValid && timeRange.start.isNumeric && timeRange.duration.isNumeric
        let length = isTimed ? timeRange.duration.seconds : 0
        meter.beginBlock(at: isTimed ? timeRange.start.seconds : nil, sampleRate: rate, secondsPerFrame: length > 0 ? length / Double(frames) : 1 / rate)

        // A buffer a channel, or one buffer with the channels side by side.
        energies.initialize(repeating: 0, count: count)
        var channels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData else { continue }
            let width = max(Int(buffer.mNumberChannels), 1)
            channels += width
            let samples = Int(buffer.mDataByteSize) / (isFloat ? 4 : 2)
            let available = min(count, samples / width)
            if isFloat {
                let values = data.assumingMemoryBound(to: Float.self)
                for frame in 0 ..< available {
                    for channel in 0 ..< width {
                        let sample = values[frame * width + channel]
                        energies[frame] += sample * sample
                    }
                }
            } else {
                let values = data.assumingMemoryBound(to: Int16.self)
                for frame in 0 ..< available {
                    for channel in 0 ..< width {
                        let sample = Float(values[frame * width + channel]) / 32768
                        energies[frame] += sample * sample
                    }
                }
            }
        }
        guard channels > 0 else { return }
        let scale = 1 / Float(channels)
        for frame in 0 ..< count {
            meter.add(energies[frame] * scale)
        }
    }
}
