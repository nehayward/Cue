import AVFoundation
import Speech

/// A chunk of audio to transcribe, and where it starts on the player's
/// timeline when that's known. Without it, times count from the first chunk
/// fed in.
struct TimedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let start: CMTime?
}

/// One word of a transcription result — with the space before it — and
/// when it starts on the audio's timeline.
struct TranscribedWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval?
}

/// The on-device speech model behind Live Transcription: Apple's
/// `SpeechAnalyzer` with a `SpeechTranscriber` for one locale, fed the
/// player's own audio. Nothing leaves the device.
///
/// Every word comes back with when it was said — on the timeline of the
/// audio fed in, when the audio says where it starts (`TimedAudio.start`) —
/// so a transcript can be shown in step with what's heard.
///
/// A language's model is downloaded the first time it's asked for and kept
/// by the system after that, shared with every app that uses it.
@available(iOS 26.0, visionOS 26.0, *)
enum TranscriptionEngine {
    enum Status: Equatable {
        /// The language's model is on its way down, 0...1.
        case downloading(Double)
        case listening
    }

    enum EngineError: LocalizedError {
        case unsupportedLocale
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "This language can't be transcribed on this device."
            case .noAudioFormat: "Transcription couldn't start."
            }
        }
    }

    /// Whether this device can run the transcriber at all.
    static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    /// Every language the transcriber can learn, installed or not.
    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    /// The transcriber's own locale for `locale` — `en-GB` for `en_GB@rg=…`
    /// and the like — or nil when it has none.
    static func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    /// Transcribes `audio` in `locale` until the task is cancelled or the
    /// audio ends. Fetches the language first if it isn't on the device.
    /// `onResult` gets each result's words with whether it's final: a
    /// volatile result is a best guess the next one replaces.
    static func run(
        locale: Locale,
        audio: AsyncStream<TimedAudio>,
        onStatus: @escaping @MainActor (Status) -> Void,
        onResult: @escaping @MainActor ([TranscribedWord], Bool) -> Void
    ) async throws {
        guard let locale = await supportedLocale(equivalentTo: locale) else {
            throw EngineError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            await onStatus(.downloading(0))
            let progress = request.progress
            let reporter = Task { @MainActor in
                while !Task.isCancelled {
                    onStatus(.downloading(progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { reporter.cancel() }
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.noAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputs, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputs)
        await onStatus(.listening)

        // Off the main actor: resampling every chunk the player plays is
        // steady work, and the analyzer wants its own format.
        let pump = Task.detached(priority: .userInitiated) {
            let converter = BufferConverter(to: format)
            for await chunk in audio {
                if let converted = converter.convert(chunk.buffer) {
                    inputBuilder.yield(AnalyzerInput(buffer: converted, bufferStartTime: chunk.start))
                }
            }
            inputBuilder.finish()
        }

        await withTaskCancellationHandler {
            do {
                for try await result in transcriber.results {
                    await onResult(words(in: result.text), result.isFinal)
                }
            } catch {
                print("Live Transcription:", error)
            }
        } onCancel: {
            pump.cancel()
            inputBuilder.finish()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}

@available(iOS 26.0, visionOS 26.0, *)
extension TranscriptionEngine {
    /// A result's text split where its timings change — a word each, with
    /// the space before it.
    fileprivate static func words(in text: AttributedString) -> [TranscribedWord] {
        text.runs.map { run in
            let start = run.audioTimeRange?.start
            return TranscribedWord(
                text: String(text[run.range].characters),
                start: start.flatMap { $0.isNumeric ? $0.seconds : nil }
            )
        }
    }
}

/// Resamples the player's audio into the analyzer's format. The source format
/// can change between songs — a 44.1 kHz file after a 48 kHz one — so the
/// converter is rebuilt whenever it does.
private final class BufferConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            // Chunks arrive back to back; priming would put a gap between each.
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
