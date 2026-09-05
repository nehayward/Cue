import Foundation

/// How long an MP3 plays, from its first frame: the Xing or VBRI header's
/// frame count when there is one, else the bit rate against the audio's
/// size, which is exact for a constant bit rate and a fair guess otherwise.
enum MP3Duration {
    struct FrameHeader {
        var version: Int       // 1, 2, or 25 for MPEG 2.5
        var layer: Int
        var bitrate: Int       // kbit/s
        var sampleRate: Int
        var isMono: Bool
        var padding: Int

        var samplesPerFrame: Int {
            switch layer {
            case 1: return 384
            case 2: return 1152
            default: return version == 1 ? 1152 : 576
            }
        }

        var frameLength: Int {
            if layer == 1 {
                return (12 * bitrate * 1000 / sampleRate + padding) * 4
            }
            let coefficient = (version == 1 || layer == 2) ? 144 : 72
            return coefficient * bitrate * 1000 / sampleRate + padding
        }

        /// Where a Xing/Info header sits: after the side information.
        var sideInformationLength: Int {
            version == 1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17)
        }
    }

    static func looksLikeFrameSync(_ view: ByteView) -> Bool {
        header(view, at: 0) != nil
    }

    static func estimate(_ source: TagByteSource, audioStart: Int, hasID3v1: Bool) -> Double? {
        guard audioStart < source.length,
              let window = try? source.read(at: audioStart, count: 64 * 1024) else { return nil }
        let view = ByteView(window)
        guard let first = firstFrame(in: view) else { return nil }
        let offset = first.offset
        let frame = first.header

        // Xing / Info: frame count in the first frame.
        let xing = offset + 4 + frame.sideInformationLength
        if view.matches(xing, "Xing") || view.matches(xing, "Info") {
            let flags = view.u32BE(xing + 4)
            if flags & 1 != 0 {
                let frames = view.u32BE(xing + 8)
                if frames > 0 {
                    return Double(frames) * Double(frame.samplesPerFrame) / Double(frame.sampleRate)
                }
            }
        }
        // VBRI: Fraunhofer's version, at a fixed offset.
        let vbri = offset + 4 + 32
        if view.matches(vbri, "VBRI") {
            let frames = view.u32BE(vbri + 14)
            if frames > 0 {
                return Double(frames) * Double(frame.samplesPerFrame) / Double(frame.sampleRate)
            }
        }

        let audioBytes = source.length - audioStart - offset - (hasID3v1 ? 128 : 0)
        guard audioBytes > 0, frame.bitrate > 0 else { return nil }
        return Double(audioBytes) * 8 / Double(frame.bitrate * 1000)
    }

    /// The first real frame in the window: one whose header parses and,
    /// where the window reaches that far, is followed by another.
    private static func firstFrame(in view: ByteView) -> (offset: Int, header: FrameHeader)? {
        var i = 0
        while i + 4 <= view.count {
            if let frame = header(view, at: i) {
                let next = i + frame.frameLength
                if next + 4 > view.count || header(view, at: next) != nil {
                    return (i, frame)
                }
            }
            i += 1
        }
        return nil
    }

    private static let bitrates: [[Int]] = [
        // index 1...14; [0] and [15] are free / bad
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],  // V1 L1
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],     // V1 L2
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],      // V1 L3
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],     // V2 L1
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],          // V2 L2, L3
    ]

    static func header(_ view: ByteView, at i: Int) -> FrameHeader? {
        guard i + 4 <= view.count, view.u8(i) == 0xFF, view.u8(i + 1) & 0xE0 == 0xE0 else { return nil }
        let b1 = view.u8(i + 1), b2 = view.u8(i + 2), b3 = view.u8(i + 3)
        let version: Int
        switch (b1 >> 3) & 0x03 {
        case 0: version = 25
        case 2: version = 2
        case 3: version = 1
        default: return nil
        }
        let layer: Int
        switch (b1 >> 1) & 0x03 {
        case 1: layer = 3
        case 2: layer = 2
        case 3: layer = 1
        default: return nil
        }
        let bitrateIndex = (b2 >> 4) & 0x0F
        let rateIndex = (b2 >> 2) & 0x03
        guard bitrateIndex > 0, bitrateIndex < 15, rateIndex < 3 else { return nil }

        let table: [Int]
        if version == 1 {
            table = bitrates[layer - 1]
        } else {
            table = layer == 1 ? bitrates[3] : bitrates[4]
        }
        let rates: [Int]
        switch version {
        case 1: rates = [44100, 48000, 32000]
        case 2: rates = [22050, 24000, 16000]
        default: rates = [11025, 12000, 8000]
        }
        return FrameHeader(
            version: version,
            layer: layer,
            bitrate: table[bitrateIndex],
            sampleRate: rates[rateIndex],
            isMono: (b3 >> 6) & 0x03 == 3,
            padding: (b2 >> 1) & 0x01
        )
    }
}
