import AVFoundation

public extension LoudnessTrace {
    /// How loud the audio file at `url` is from `start` to `end`, seconds
    /// on its own clock: for Smart Resume on a file that's on the device.
    /// A few seconds read take a few milliseconds. Nil when it can't be
    /// read.
    static func reading(_ url: URL, from start: TimeInterval, to end: TimeInterval) -> LoudnessTrace? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        let channelCount = Int(format.channelCount)
        guard rate > 0, channelCount > 0 else { return nil }
        let first = AVAudioFramePosition(max(start, 0) * rate)
        let last = min(AVAudioFramePosition(max(end, 0) * rate), file.length)
        guard last > first, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return nil }
        file.framePosition = first
        var meter = LoudnessMeter()
        meter.beginBlock(at: Double(first) / rate, sampleRate: rate, secondsPerFrame: 1 / rate)
        var position = first
        let scale = 1 / Float(channelCount)
        while position < last {
            let wanted = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), last - position))
            do {
                try file.read(into: buffer, frameCount: wanted)
            } catch {
                return nil
            }
            let frames = Int(buffer.frameLength)
            // The processing format is always float, a buffer a channel.
            guard frames > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0 ..< frames {
                var energy: Float = 0
                for channel in 0 ..< channelCount {
                    let sample = channels[channel][frame]
                    energy += sample * sample
                }
                meter.add(energy * scale)
            }
            position += AVAudioFramePosition(frames)
        }
        return meter.trace.times.isEmpty ? nil : meter.trace
    }
}
