import Foundation

/// The arithmetic behind `VibeSlider` and `VibeSliderTV`, kept free of any
/// assumption a caller can break.
///
/// The sliders used to divide by the range's upper bound. That assumed the
/// range starts at zero, that it is not empty, and that the value sits
/// inside it — and the player's scrubber breaks the last two at once on a
/// radio source: Sonos reports no duration for a stream, so the range is
/// `0...0`, while the position keeps counting up. `value / 0` is then
/// infinity for the fill width (or NaN when the value is zero too), which
/// is not geometry SwiftUI can lay out, and the accessibility `Slider` was
/// built over the same empty range.
///
/// Everything here goes through `safeRange`, which is never empty, and
/// `clamped`, which keeps a value finite and inside it.
struct SliderMath {
    let range: ClosedRange<Double>

    /// The range the slider draws and scrubs over. Non-finite bounds are
    /// dropped, and an empty range is widened by one so there is always a
    /// span to divide by.
    var safeRange: ClosedRange<Double> {
        let lower = range.lowerBound.isFinite ? range.lowerBound : 0
        let upper = range.upperBound.isFinite ? range.upperBound : lower
        return upper > lower ? lower...upper : lower...(lower + 1)
    }

    var span: Double { safeRange.upperBound - safeRange.lowerBound }

    /// `value` held inside `safeRange`; a non-finite value rests at the
    /// lower bound.
    func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return safeRange.lowerBound }
        return min(max(safeRange.lowerBound, value), safeRange.upperBound)
    }

    /// How far along the track `value` sits, 0…1.
    func fraction(of value: Double) -> Double {
        (clamped(value) - safeRange.lowerBound) / span
    }

    /// The width of the fill for `value` on a track `trackWidth` wide.
    func fillWidth(for value: Double, trackWidth: Double) -> Double {
        guard trackWidth.isFinite, trackWidth > 0 else { return 0 }
        return fraction(of: value) * trackWidth
    }

    /// The value at `fraction` of the way along the track.
    func value(atFraction fraction: Double) -> Double {
        guard fraction.isFinite else { return safeRange.lowerBound }
        return clamped(safeRange.lowerBound + fraction * span)
    }

    /// The value a drag of `translation` points across a track `trackWidth`
    /// wide moves `start` to, snapped to `step`.
    func value(from start: Double, translation: Double, trackWidth: Double, step: Double) -> Double {
        guard trackWidth.isFinite, trackWidth > 0, translation.isFinite else { return clamped(start) }
        let diff = max(min(translation, trackWidth), -trackWidth) / trackWidth * span
        let stepped = step > 0 && step.isFinite ? (diff / step).rounded() * step : diff
        return clamped(clamped(start) + stepped)
    }
}
