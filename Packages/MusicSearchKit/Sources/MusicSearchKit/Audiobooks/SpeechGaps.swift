import Foundation

/// How loud a stretch of a book's audio was, in short windows: what Smart
/// Resume reads to start again in a pause between words, not in a word.
public struct LoudnessTrace: Sendable, Equatable {
    /// Where each window starts, in seconds, in order and without breaks.
    public var times: [TimeInterval]
    /// Each window's loudness, in dB below full scale.
    public var levels: [Float]
    /// How long a window lasts.
    public var windowLength: TimeInterval

    public init(times: [TimeInterval] = [], levels: [Float] = [], windowLength: TimeInterval = LoudnessMeter.windowLength) {
        self.times = times
        self.levels = levels
        self.windowLength = windowLength
    }

    /// Where the last window ends; nil with none.
    public var end: TimeInterval? {
        times.last.map { $0 + windowLength }
    }

    /// The same windows, `offset` seconds later: from a file's clock to the
    /// book's, say.
    public func shifted(by offset: TimeInterval) -> LoudnessTrace {
        LoudnessTrace(times: times.map { $0 + offset }, levels: levels, windowLength: windowLength)
    }
}

/// Turns audio into a `LoudnessTrace` a block at a time, as it comes: from
/// the player as it plays, or read from a file. It keeps the last
/// `capacity` windows of audio that ran on without a break.
public struct LoudnessMeter: Sendable {
    public static let windowLength: TimeInterval = 0.01

    public private(set) var trace = LoudnessTrace()
    /// Whether the times are the file's own. False while they're only
    /// counted from the first block, which came with no time.
    public private(set) var isAnchored = false

    private let capacity: Int
    private var hasStarted = false
    private var windowFrames = 441
    private var blockStart: TimeInterval = 0
    private var secondsPerFrame: TimeInterval = 1.0 / 44100
    private var framesInBlock = 0
    private var windowStart: TimeInterval = 0
    private var windowSum: Double = 0
    private var windowCount = 0

    /// Half a minute of windows: more than Smart Resume goes back.
    public init(capacity: Int = 3000) {
        self.capacity = capacity
        trace.times.reserveCapacity(capacity + capacity / 4 + 1)
        trace.levels.reserveCapacity(capacity + capacity / 4 + 1)
    }

    /// Starts a block of audio whose first frame is at `time` on the
    /// file's clock (nil: straight after the last block), `sampleRate`
    /// frames a second, each frame `secondsPerFrame` of the file. A block
    /// that doesn't follow on from the last starts the trace over.
    public mutating func beginBlock(at time: TimeInterval?, sampleRate: Double, secondsPerFrame: TimeInterval) {
        let frames = max(Int((sampleRate * Self.windowLength).rounded()), 1)
        let expected = blockStart + Double(framesInBlock) * self.secondsPerFrame
        if let time {
            let followsOn = hasStarted && isAnchored && frames == windowFrames
                && abs(time - expected) <= Self.continuityTolerance
            if !followsOn { reset() }
            isAnchored = true
            blockStart = time
        } else if hasStarted, frames == windowFrames {
            blockStart = expected
        } else {
            reset()
            isAnchored = false
            blockStart = 0
        }
        windowFrames = frames
        self.secondsPerFrame = secondsPerFrame > 0 ? secondsPerFrame : 1 / max(sampleRate, 1)
        framesInBlock = 0
        hasStarted = true
    }

    /// Adds the block's next frame: the mean of its channels' squared
    /// samples.
    public mutating func add(_ energy: Float) {
        if windowCount == 0 {
            windowStart = blockStart + Double(framesInBlock) * secondsPerFrame
        }
        windowSum += Double(energy)
        windowCount += 1
        framesInBlock += 1
        guard windowCount >= windowFrames else { return }
        append(start: windowStart, level: Self.decibels(windowSum / Double(windowCount)))
        windowSum = 0
        windowCount = 0
    }

    /// Forgets everything: a seek, a new file.
    public mutating func reset() {
        trace.times.removeAll(keepingCapacity: true)
        trace.levels.removeAll(keepingCapacity: true)
        windowSum = 0
        windowCount = 0
        hasStarted = false
    }

    private mutating func append(start: TimeInterval, level: Float) {
        trace.times.append(start)
        trace.levels.append(level)
        trace.windowLength = Double(windowFrames) * secondsPerFrame
        // Trimmed in batches: each trim moves the whole array along.
        if trace.times.count > capacity + capacity / 4 {
            let extra = trace.times.count - capacity
            trace.times.removeFirst(extra)
            trace.levels.removeFirst(extra)
        }
    }

    /// How far a block may start from where the last one ended and still
    /// follow on from it.
    private static let continuityTolerance: TimeInterval = 0.25

    static func decibels(_ meanSquare: Double) -> Float {
        Float(10 * log10(max(meanSquare, 1e-10)))
    }
}

/// Finds where speech pauses in a `LoudnessTrace`: the stretches much
/// quieter than the voice around them. A pause of a third of a second or
/// more is most likely the end of a sentence; a tenth of a second, a gap
/// between words.
public enum SpeechGaps {
    /// Where to start again near `target`: in the nearest pause in the
    /// speech heard before `limit` (where it was paused), never before
    /// `floor` and never later than a moment before `limit`. With
    /// `prefersSentences`, a long pause up to a couple of seconds further
    /// back wins over a short one nearer. Nil when the trace doesn't reach
    /// the target, its speech and silence aren't clearly apart (music, a
    /// noisy recording), or no pause is near.
    public static func landing(near target: TimeInterval, before limit: TimeInterval, notBefore floor: TimeInterval = 0, prefersSentences: Bool, in trace: LoudnessTrace) -> TimeInterval? {
        guard let first = trace.times.first, let end = trace.end,
              first <= target - 0.25, end >= min(target + 0.1, limit) else { return nil }

        // How loud the voice is around the target, and how quiet its pauses.
        var nearby: [Float] = []
        for (time, level) in zip(trace.times, trace.levels) where time >= target - 5 && time <= min(target + 3, limit) {
            nearby.append(level)
        }
        guard nearby.count >= 100 else { return nil }
        nearby.sort()
        let quietest = max(nearby[nearby.count * 5 / 100], noiseFloor)
        let voice = nearby[nearby.count * 90 / 100]
        guard voice - quietest >= minimumContrast else { return nil }
        let threshold = quietest + (voice - quietest) * quietFraction

        // The quiet runs from a little before the furthest reach up to the pause.
        var gaps: [(start: TimeInterval, end: TimeInterval)] = []
        var runStart: TimeInterval?
        for (time, level) in zip(trace.times, trace.levels) {
            if time < target - sentenceReach - 1 { continue }
            if time >= limit { break }
            if level < threshold {
                if runStart == nil { runStart = time }
            } else if let start = runStart {
                gaps.append((start, time))
                runStart = nil
            }
        }
        if let start = runStart {
            gaps.append((start, min(end, limit)))
        }

        let latest = limit - minimumRewind
        func best(longerThan length: TimeInterval, within reach: TimeInterval, after: TimeInterval) -> TimeInterval? {
            var choice: (landing: TimeInterval, cost: TimeInterval)?
            for gap in gaps where gap.end - gap.start >= length {
                // A little before the voice comes back, or the middle of a short pause.
                let landing = max(gap.start + (gap.end - gap.start) / 2, gap.end - leadIn)
                guard landing >= floor, landing <= latest,
                      landing >= target - reach, landing <= target + after else { continue }
                // Going back further than asked is the safer miss.
                let cost = landing < target ? target - landing : (landing - target) * 2
                if choice.map({ cost < $0.cost }) ?? true {
                    choice = (landing, cost)
                }
            }
            return choice?.landing
        }
        let sentence = best(longerThan: sentencePause, within: sentenceReach, after: 0.75)
        let word = best(longerThan: wordPause, within: 1, after: 0.4)
        return prefersSentences ? sentence ?? word : word ?? sentence
    }

    /// The shortest pauses that count.
    static let wordPause: TimeInterval = 0.1
    static let sentencePause: TimeInterval = 0.35
    /// How much further back than asked a sentence's end is looked for.
    static let sentenceReach: TimeInterval = 2
    /// How long before the voice comes back to start, in a long pause.
    static let leadIn: TimeInterval = 0.12
    /// Always back at least this far from where it was paused.
    static let minimumRewind: TimeInterval = 0.3
    /// Room tone below this is as quiet as it needs to be.
    static let noiseFloor: Float = -70
    static let minimumContrast: Float = 15
    /// How far from the quiet towards the voice a window is still quiet.
    static let quietFraction: Float = 0.3
}
