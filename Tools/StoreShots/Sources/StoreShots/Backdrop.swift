import SwiftUI

/// The background behind a shot: a mesh gradient through the palette that
/// carries on from one shot into the next, so the set reads as one strip in
/// the store. Each shot is three columns of the strip's mesh: its left edge
/// is the column its left neighbour ends on.
struct Backdrop: View {
    let theme: Theme
    /// The shot's place in the set.
    let index: Int

    var body: some View {
        let columns = (0...2).map { column(2 * index + $0) }
        MeshGradient(
            width: 3, height: 4,
            points: (0..<4).flatMap { row in
                (0..<3).map { column in
                    SIMD2<Float>(Float(column) / 2 + (column == 1 ? jitter(2 * index + 1, row, 0.14) : 0),
                                 Float(row) / 3 + (row == 0 || row == 3 ? 0 : jitter(2 * index + column, row, 0.07)))
                }
            },
            colors: (0..<4).flatMap { row in columns.map { $0[row].color } },
            smoothsColors: true
        )
        .overlay {
            // Grain, so the gradient doesn't band when the store recompresses it.
            Grain()
        }
    }

    /// One column of the strip, top to bottom: dark, the palette colour, a
    /// deeper version of it, dark.
    private func column(_ k: Int) -> [HexColor] {
        let palette = theme.palette.isEmpty ? [theme.base] : theme.palette
        let here = palette[(k / 2) % palette.count]
        let next = palette[(k / 2 + 1) % palette.count]
        let color = k % 2 == 0 ? here : here.mixed(with: next, 0.5)
        let glow = jitter(k, 9, 0.5) + 0.5
        return [
            theme.base.mixed(with: color, 0.28 + 0.1 * Double(glow)),
            color.mixed(with: theme.base, 0.12),
            theme.base.mixed(with: color, 0.5),
            theme.base,
        ]
    }

    /// A small fixed offset for a mesh point, the same for both shots that share it.
    private func jitter(_ k: Int, _ row: Int, _ amount: Float) -> Float {
        var seed = UInt64(truncatingIfNeeded: k &* 73_856_093 ^ row &* 19_349_663) &+ 0x9E37_79B9_7F4A_7C15
        seed = (seed ^ (seed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        seed = (seed ^ (seed >> 27)) &* 0x94D0_49BB_1331_11EB
        seed ^= seed >> 31
        return (Float(seed % 10_000) / 10_000 - 0.5) * 2 * amount
    }
}

/// Fine noise, a few percent strong.
private struct Grain: View {
    var body: some View {
        Image(decorative: Self.tile, scale: 1)
            .resizable(resizingMode: .tile)
            .opacity(0.05)
            .blendMode(.overlay)
    }

    static let tile: CGImage = {
        let side = 256
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var state: UInt32 = 0x1234_5678
        for pixel in 0..<(side * side) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            let value = UInt8(truncatingIfNeeded: state)
            bytes[pixel * 4] = value
            bytes[pixel * 4 + 1] = value
            bytes[pixel * 4 + 2] = value
        }
        let context = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }()
}
