import Foundation

/// A sort key that orders the way Finder does — case and accents ignored,
/// numbers by their value — but as a plain string, so a list of thousands
/// sorts with `<` in milliseconds instead of a localized comparison per
/// pair. Compute it once per item, sort on it many times.
public enum NaturalSortKey {
    /// Digit runs are zero-padded to this width, so "Track 2" sorts before
    /// "Track 10". A run longer than this is left as it is.
    private static let digitWidth = 12

    public static func key(for string: String) -> String {
        let folded = string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        var digits = String.UnicodeScalarView()

        func flush() {
            guard !digits.isEmpty else { return }
            let padding = digitWidth - digits.count
            if padding > 0 {
                out.append(contentsOf: repeatElement("0", count: padding))
            }
            out.append(contentsOf: digits)
            digits.removeAll(keepingCapacity: true)
        }

        for scalar in folded.unicodeScalars {
            if scalar.value >= 48, scalar.value <= 57 {
                digits.append(scalar)
            } else {
                flush()
                out.append(scalar)
            }
        }
        flush()
        return String(out)
    }
}
