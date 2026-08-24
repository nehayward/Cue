import UIKit

extension String {
    /// A normalized form suitable for "fuzzy" equality:
    /// - ignores case
    /// - ignores diacritics (é == e)
    /// - uses the provided locale (defaults to current)
    func normalizedForDedup(locale: Locale = .current) -> String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Sequence {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}


extension String {
    func removingPrefix(
        _ prefix: String,
        locale: Locale = .current
    ) -> String {
        guard !prefix.isEmpty else { return self }

        if let range = range(
            of: prefix,
            options: [.anchored, .caseInsensitive],
            locale: locale
        ) {
            return String(self[range.upperBound...])
        }

        return self
    }
}
