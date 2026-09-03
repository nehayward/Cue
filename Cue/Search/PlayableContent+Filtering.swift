import MusicSearchKit
import SonosKit

extension Array where Element == PlayableContent {
    /// Returns the items whose content type is included by the active filter selections.
    /// When no filter is active, returns the array unchanged.
    func filtered(by filters: [FilterSelection]) -> [PlayableContent] {
        let active = filters.filter(\.isFiltered)
        guard !active.isEmpty else { return self }
        let activeTypes = Set(active.flatMap(\.filter.toContentType))
        return self.filter { activeTypes.contains($0.content.type) }
    }
}
